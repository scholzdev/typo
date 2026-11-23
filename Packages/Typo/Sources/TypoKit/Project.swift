import Foundation
import Observation
import TypstEngine
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

public struct FileNode: Identifiable, Sendable, Equatable {
    public let id: RelPath
    public let isDirectory: Bool
    public let children: [FileNode]?

    public init(id: RelPath, isDirectory: Bool, children: [FileNode]?) { self.id = id; self.isDirectory = isDirectory; self.children = children }

    @concurrent static func scan(_ root: URL) async -> [FileNode] { list(root, prefix: "") }
    /// Same scan on the caller's thread, for operations that must not suspend between a disk change and the tree.
    static func scanNow(_ root: URL) -> [FileNode] { list(root, prefix: "") }

    private static func list(_ dir: URL, prefix: String) -> [FileNode] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        return urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }.compactMap { u in
            guard let id = RelPath(prefix + u.lastPathComponent) else { return nil }
            let isDir = (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return FileNode(id: id, isDirectory: isDir, children: isDir ? list(u, prefix: id.raw + "/") : nil)
        }
    }
}

/// One per window. Owns the buffers, the edit log, the latest result, and the save schedule.
@MainActor @Observable public final class Project {
    public let id: ProjectID
    public internal(set) var files: [FileNode] { didSet { syncProjectFonts() } }
    public internal(set) var main: RelPath
    public var selectedFile: RelPath? {
        didSet {
            guard let f = selectedFile else { return }
            tabs.show(f, permanent: false, pinning: navigation.pinTabs)
            // Register the read before the next render, so the editor sees `isOpening(f)` and keeps its
            // held buffer instead of flashing the empty state and rebuilding the text view.
            startOpening(f)
            Task { _ = try? await open(f) }
        }
    }
    /// Assigned by the app from its Navigation settings.
    @ObservationIgnored public var navigation = NavigationSettings.standard
    /// Set by the window: shows a file in the split editor's second pane.
    @ObservationIgnored public var showInSecondPane: ((RelPath, _ permanent: Bool) -> Void)?
    /// The one place navigation targets (jumps, results, Quick Open) are resolved to a pane; false when the second took it.
    @discardableResult
    func navigate(to file: RelPath, permanent: Bool = false) -> Bool {
        guard navigation.pane(for: file, first: selectedFile, focusedSecond: focusedEditorFile) == .second, let showInSecondPane else {
            selectedFile = file
            return true
        }
        showInSecondPane(file, permanent)
        return false
    }
    /// The first editor pane's tabs (design/14h), derived from `selectedFile`; persisted per project.
    public internal(set) var tabs = TabList() { didSet { if tabs != oldValue { saveTabs() } } }
    public var selectedBuffer: Buffer? { selectedFile.flatMap { buffers[$0] } }
    /// The buffer of `path` if it is already open; no reading.
    public func openBuffer(_ path: RelPath) -> Buffer? { buffers[path] }
    /// True while `open(_:)` is still reading `path` from disk.
    public func isOpening(_ path: RelPath) -> Bool { opening[path] != nil }
    /// The file of a second editor pane while it has keyboard focus; nil while the main editor (`selectedFile`) has it.
    /// Completion and the preview's cursor sync follow the focused editor.
    @ObservationIgnored public var focusedEditorFile: RelPath?
    var activeFile: RelPath? { focusedEditorFile ?? selectedFile }
    public private(set) var status: CompileStatus = .idle
    /// True from the first unsaved edit until a save has written every dirty buffer. The app reads it
    /// to hold off sudden termination.
    public internal(set) var hasUnsavedChanges = false
    /// Bumped when a buffer turns dirty and after every save, so views showing per-file dirty state (tabs) refresh.
    public internal(set) var dirtyRevision = 0
    /// File and reason of the last failed save, nil once a save succeeds. Never cleared by anything else.
    public private(set) var saveError: String?
    /// Bumped each time `reveal` queues a selection, so a view showing the already-selected file reruns.
    public private(set) var selectionRequests = 0
    public let preview = PreviewModel()
    /// Locked (default): the preview stays on the pinned document, which is `main`. Unlocked: selecting a `.typ`
    /// file in the sidebar makes it the previewed document. Persisted per project in RecentProjects.
    public var previewLocked = true { didSet { recents?.setLocked(previewLocked, for: id) } }
    /// False compiles only on save and on explicit requests (the app's "On Save" live preview).
    @ObservationIgnored public var compilesWhileTyping = true { didSet { engine.setDefersEdits(!compilesWhileTyping) } }
    @ObservationIgnored public var autosaveDelay: Duration? = .seconds(1.5)

    /// Bumped by every edit to a bibliography file, so the References tab knows to reparse.
    public internal(set) var bibliographyRevision = 0
    /// Bumped whenever the file tree changes (a file operation or an external change), so the search can rerun.
    public internal(set) var fileRevision = 0 { didSet { scheduleLint() } }
    /// Off: no lint hints are computed or shown. The app sets it from its setting.
    public var lintEnabled = true { didSet { if lintEnabled != oldValue { scheduleLint() } } }
    /// On: the PDF/UA pre-flight (Accessibility.swift) adds its hints, also with lint hints off. The app sets it from its setting and the export target.
    public var accessibilityChecks = false { didSet { if accessibilityChecks != oldValue { scheduleLint() } } }
    /// Off: no inlay hints are computed and the buffers drop their gaps. The app sets it from its setting.
    @ObservationIgnored public var inlayHintsEnabled = false {
        didSet {
            guard inlayHintsEnabled != oldValue else { return }
            if !inlayHintsEnabled { inlay = nil; syncAllKerns() }
            scheduleInlayHints()
        }
    }
    var buffers: [RelPath: Buffer] = [:]             // opened on demand, kept until the window closes
    var opening: [RelPath: Task<Buffer, any Error>] = [:]   // in-flight opens; see open(_:)
    private var nextSeq = Seq(raw: 1)
    /// Paths that moved or went to the Trash; results of compiles before `staleSince` still name them.
    /// Diagnostics and outline entries under them are hidden until a compile covers the change (the outline
    /// follows the last successful one).
    var staleRoots: [RelPath] = []
    var staleSince = Seq(raw: 0)
    var autosavePauses = 0
    var filesGeneration = 0
    /// The font files the engine's world last got; see syncProjectFonts().
    @ObservationIgnored var projectFontPaths: [String] = []
    var fileOpBusy = false
    /// File identity of each open buffer's path (see FileOperations `followExternalMoves`): a Finder rename keeps it.
    var identities: [RelPath: any NSObjectProtocol] = [:]
    var fileOpWaiters: [CheckedContinuation<Void, Never>] = []
    /// Moves a file to the Trash and returns where it went. Tests replace it so they never touch the user's Trash.
    @ObservationIgnored var trash: @MainActor (URL) throws -> URL = { url in
        var out: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &out)
        return (out as URL?) ?? url
    }
    /// Open files whose file was deleted outside the app (design/14d-files-safety.md); saves skip them.
    var missingFiles: Set<RelPath> = []
    /// Open files with unsaved text whose disk content changed behind our back; saves skip them (ExternalChanges.swift).
    public internal(set) var changedOnDisk: Set<RelPath> = []
    /// Hash of the text each open file had when last read from or written to disk.
    @ObservationIgnored var diskHashes: [RelPath: Int] = [:]
    /// Files an agent's own tool is rewriting, with how many calls hold each: reload and save skip them (ExternalChanges.swift).
    @ObservationIgnored var reloadHolds: [RelPath: Int] = [:]
    /// Snapshots after saves (design/14d-files-safety.md); off until the app sets `history.folder`.
    @ObservationIgnored public var history = LocalHistory()
    var log = EditLog()
    /// Code bookmarks, saved per project (see CodeBookmarks.swift).
    public internal(set) var bookmarks: [CodeBookmark] = [] { didSet { bookmarksDidChange(from: oldValue) } }
    /// Each open file's bookmarked line ranges, moved by every edit; not observed, as they change with typing.
    @ObservationIgnored var bookmarkAnchors: [UUID: NSRange] = [:]
    /// The Zotero library synced into a `.bib` file, saved per project (ZoteroSync.swift).
    public internal(set) var zoteroLink: ZoteroLink? { didSet { if zoteroLink != oldValue { ZoteroLinkStore(id).save(zoteroLink) } } }
    /// Why the last Zotero sync failed, nil after a successful one.
    public internal(set) var zoteroError: String?
    public internal(set) var zoteroSyncing = false
    /// No sync before this: Zotero asked to back off (Retry-After, Backoff).
    @ObservationIgnored var zoteroNotBefore: Date?
    private var result: CompileResult?                       // latest delivered, never older than the previous one
    private var lastGood: CompileResult?                     // latest result with a document: what the preview and the outline show
    private var lint: (seq: Seq, hints: [Diagnostic])?       // lint hints of the texts as of `seq`; see runLint()
    @ObservationIgnored private var lintTask: Task<Void, Never>?
    @ObservationIgnored var inlay: (seq: Seq, hints: [RelPath: [InlayHint]])?     // see runInlayHints()
    @ObservationIgnored var inlayTask: Task<Void, Never>?
    var latestSearch = 0
    var searchTask: Task<SearchOutcome?, Never>?
    @ObservationIgnored var bibIndex: (revision: Int, entries: [String: BibEntry])?     // see enrichedWithBibliography
    var activeList: CompletionList?                  // the one list `live` serves; see trimLog()
    var inflightRequests: [Seq] = []                 // seq of each unanswered completion request or running lint
    private var latestRequest = 0
    private var latestCursorRequest = 0
    private var latestClickRequest = 0
    private var latestHoverRequest = 0
    var lastCursor: (file: RelPath, cursor: Int)?     // the selected file's caret, for post-compile re-syncs
    var cursorSeqs: [RelPath: Seq] = [:]              // buffer.lastSeq when the caret was last reported
    public let engine: Engine
    let root: URL
    let runtime: TypstRuntime
    private let access: ScopedAccess?
    weak var recents: RecentProjects?
    var autosave: Task<Void, Never>?
    var saving: Task<Void, Never>?
    private var eventsTask: Task<Void, Never>?
    private var packagesTask: Task<Void, Never>?

    /// Test support.
    @ObservationIgnored var eventTap: (@MainActor (EngineEvent) -> Void)?
    private(set) var resyncCount = 0

    public static func open(_ id: ProjectID, recents: RecentProjects,
                            textFileSettings: @escaping () -> TextFileSettings = { TextFileSettings() }) async throws(ProjectError) -> Project {
        guard let rec = recents.record(id) else { throw .accessDenied }
        let access = try ScopedAccess(resolving: rec.bookmark, fallbackPath: rec.rootPath)
        if access.isStale { recents.refreshBookmark(id, root: access.root) }
        let runtime = await TypstRuntime.shared.value
        let p = try await Project(id: id, root: access.root, main: rec.main, runtime: runtime, access: access, textFileSettings: textFileSettings)
        p.previewLocked = rec.locked ?? true     // before `recents` is set, so it is not written back
        p.recents = recents
        return p
    }

    public init(id: ProjectID, root: URL, main: RelPath, runtime: TypstRuntime, access: ScopedAccess? = nil,
         textFileSettings: @escaping () -> TextFileSettings = { TextFileSettings() }) async throws(ProjectError) {
        self.textFileSettings = textFileSettings
        self.id = id
        self.root = root
        self.runtime = runtime
        self.main = main
        self.access = access
        self.files = []
        self.engine = try Engine(runtime: runtime, root: root, main: main)
        let events = engine.events
        eventsTask = Task { [weak self] in
            for await e in events {
                guard let self else { return }
                self.handle(e)
            }
        }
        let changes = runtime.packagesChanges()
        packagesTask = Task { [weak self] in
            for await _ in changes { self?.engine.send(.recompile) }
        }
        // A project whose main was trashed (no other .typ left) must still open, with nothing selected.
        tabs = restoredTabs()
        bookmarks = BookmarkStore(id).load().filter { exists($0.path) }
        zoteroLink = ZoteroLinkStore(id).load()
        if FileManager.default.fileExists(atPath: root.appending(path: main.raw).path) {
            try await open(main)
            selectedFile = main
        }
        files = await FileNode.scan(root)
        syncProjectFonts()                // observers do not run in init
    }

    isolated deinit {
        engine.close()
        eventsTask?.cancel()
        packagesTask?.cancel()
        autosave?.cancel()
        lintTask?.cancel()
        inlayTask?.cancel()
    }

    func takeSeq() -> Seq { defer { nextSeq = Seq(raw: nextSeq.raw + 1) }; return nextSeq }
    var lastRecordedSeq: Seq { Seq(raw: nextSeq.raw - 1) }

    /// Set by the app from its settings; read at every open, reload and save, so changes apply at once.
    @ObservationIgnored public var textFileSettings: () -> TextFileSettings = { TextFileSettings() }

    /// The file's text with LF line endings, and the format to write it back in. Not valid UTF-8 and not
    /// decodable with the fallback: throws.
    @concurrent static func readFile(_ url: URL, settings: TextFileSettings) async throws -> (text: String, format: FileFormat) {
        guard let r = TextFile.decode(try Data(contentsOf: url), settings: settings) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        return r
    }

    @concurrent static func readText(_ url: URL, settings: TextFileSettings) async throws -> String {
        try await readFile(url, settings: settings).text
    }

    /// Reads the file off-main and creates its Buffer. The overlay is seeded with exactly that text.
    /// Idempotent, also under concurrency: a sidebar click and a reveal racing across the disk-read
    /// suspension both await the same `opening[path]` task, so one file never gets two storages.
    @discardableResult public func open(_ path: RelPath) async throws(ProjectError) -> Buffer {
        if let b = buffers[path] { return b }
        let task = startOpening(path)
        do {
            let b = try await task.value
            opening[path] = nil
            return b
        } catch {
            opening[path] = nil
            throw .unreadable(path)
        }
    }

    /// The shared disk-read task for `path`, created and registered in `opening` synchronously.
    @discardableResult private func startOpening(_ path: RelPath) -> Task<Buffer, any Error> {
        if let t = opening[path] { return t }
        if let b = buffers[path] { return Task { b } }
        let url = root.appending(path: path.raw)
        let settings = self.textFileSettings()
        let task = Task {
            let (text, format) = try await Self.readFile(url, settings: settings)
            let b = Buffer(path: path, text: text, seq: self.takeSeq(), project: self)
            b.fileFormat = format
            self.engine.send(.setText(path, text, b.lastSeq))
            self.buffers[path] = b
            self.anchorBookmarks(in: b)
            self.diskHashes[path] = text.hashValue
            self.identify(path)
            return b
        }
        opening[path] = task
        return task
    }

    /// Called only by Buffer's delegate. Order is the order of the calls: log, engine, autosave.
    func record(_ path: RelPath, _ pre: NSRange, _ text: String, newLength: Int) {
        let e = Edit(seq: takeSeq(), file: path, range: pre, replacement: text, newLength: newLength)
        if buffers[path]?.isDirty == false { dirtyRevision += 1 }
        buffers[path]?.lastSeq = e.seq
        hasUnsavedChanges = true
        if tabs.preview == path { tabs.makePermanent(path) }
        if BibliographyFile.isBibliography(path.raw) { bibliographyRevision += 1 }
        log.append(e)
        engine.send(.edit(e))
        scheduleAutosave()
    }

    /// Derived, never stored: the latest result's diagnostics mapped through the edits it did not see.
    /// Marks, the list, and reveal all read this, so they always agree with the current text.
    /// A file unopened at compile time was read from disk; a Buffer opened later starts from that
    /// same text and logs only later edits, so the mapping stays exact.
    public var diagnostics: [Diagnostic] { mappedDiagnostics(in: nil) }

    /// Maps only the diagnostics of `file` (all of them when nil), so a per-file query does not walk the edit
    /// log for every other file's diagnostics on each keystroke.
    private func mappedDiagnostics(in file: RelPath?) -> [Diagnostic] {
        guard let result else { return [] }
        return result.snapshot.diagnostics.compactMap { d in
            guard case .project(let loc) = d.origin else { return file == nil ? d : nil }
            if let file, loc.file != file { return nil }
            if result.seq < staleSince, staleRoots.contains(where: loc.file.isAtOrUnder) { return nil }
            return log.map(loc.range, in: loc.file, from: result.seq).map { d.with(range: $0) }   // nil = edited away
        }
    }

    /// Lint hints (severity `.hint`), mapped through later edits like `diagnostics`; empty while lint is off.
    public var lintHints: [Diagnostic] { mappedHints(in: nil) }

    public func lintHints(in file: RelPath) -> [Diagnostic] { mappedHints(in: file) }

    private func mappedHints(in file: RelPath?) -> [Diagnostic] {
        guard lintEnabled || accessibilityChecks, let lint else { return [] }
        return lint.hints.compactMap { d in
            guard case .project(let loc) = d.origin, file == nil || loc.file == file else { return nil }
            if lint.seq < staleSince, staleRoots.contains(where: loc.file.isAtOrUnder) { return nil }
            return log.map(loc.range, in: loc.file, from: lint.seq).map { d.with(range: $0) }
        }
    }

    /// Reruns the lint 600 ms after the last compile or file change; a newer call supersedes a pending one.
    private func scheduleLint() {
        lintTask?.cancel()
        lintTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await self?.runLint()
        }
    }

    /// Lints the current texts (open buffers win over disk) off-main and stores the hints with the seq they saw.
    func runLint() async {
        guard lintEnabled || accessibilityChecks else { lint = nil; return }
        let seq = lastRecordedSeq
        let sources = textSources { FileKind.isTypst($0) || BibliographyFile.isBibliography($0) }
        func walk(_ nodes: [FileNode]) -> [RelPath] { nodes.flatMap { [$0.id] + walk($0.children ?? []) } }
        let compiler = diagnostics.compactMap { d -> Location? in if case .project(let l) = d.origin { l } else { nil } }
        inflightRequests.append(seq)         // keeps the edits after `seq` in the log until the hints are stored
        let hints = await Self.lint(sources, existing: Set(walk(files)), compiler: compiler, main: main, lints: lintEnabled, accessibility: accessibilityChecks)
        inflightRequests.remove(at: inflightRequests.firstIndex(of: seq)!)
        if !Task.isCancelled, lintEnabled || accessibilityChecks { lint = (seq, hints) }
        trimLog()
    }

    @concurrent private static func lint(_ sources: [SearchSource], existing: Set<RelPath>, compiler: [Location], main: RelPath, lints: Bool, accessibility: Bool) async -> [Diagnostic] {
        let loaded = sources.compactMap(\.loaded)
        var hints = lints ? Lint.hints(LabelIndex.build(loaded), sources: loaded, existing: existing, compiler: compiler) : []
        if lints, loaded.contains(where: { $0.text.contains("@preview/") }) {
            hints += PackageUpdates.hints(sources: loaded, index: await TypstRuntime.universePackages(), firstID: hints.count)
        }
        return hints + (accessibility ? Accessibility.hints(sources: loaded, main: main, firstID: hints.count) : [])
    }

    /// Nil until the file has been opened; the app uses it to turn a diagnostic's range into a line number.
    public func buffer(for path: RelPath) -> Buffer? { buffers[path] }
    public var openBuffers: [Buffer] { Array(buffers.values) }

    public func diagnostics(in file: RelPath) -> [Diagnostic] {
        mappedDiagnostics(in: file)
    }

    public func reveal(_ d: Diagnostic) {
        guard case .project(let loc) = d.origin else { return }
        show(loc.file, range: loc.range)
    }

    /// Opens `file` and selects `range` (clamped by the editor), optionally with the find indicator.
    public func show(_ file: RelPath, range: NSRange, flash: Bool = false) {
        recordVisit(NavPlace(file: file, offset: range.location))
        navigate(to: file)
        Task {
            try? await open(file).requestSelection(range, flash: flash)
            selectionRequests += 1
        }
    }

    /// Headings of the document the preview shows (the last successful compile), offsets mapped through the
    /// edits that compile did not see. A heading whose start was edited away is dropped.
    public var outline: [OutlineItem] {
        guard let r = lastGood else { return [] }
        return r.snapshot.outline.compactMap { h in
            if r.seq < staleSince, staleRoots.contains(where: h.file.isAtOrUnder) { return nil }
            return log.map(NSRange(location: h.offset, length: 0), in: h.file, from: r.seq).map { h.with(offset: $0.location) }
        }
    }

    /// Jumps the editor to the heading and aims the preview at it.
    public func reveal(_ h: OutlineItem) {
        show(h.file, range: NSRange(location: h.offset, length: 0), flash: true)
        preview.aim(PreviewPosition(page: h.page, point: CGPoint(x: 0, y: h.y)), SyncDecision(request: false, scrollIfOutside: true, marker: true))
    }

    public var rootURL: URL { root }

    public func url(for path: RelPath) -> URL { root.appending(path: path.raw) }

    /// Every file below the root (hidden ones are not scanned), in tree order.
    public var allFiles: [RelPath] { files.flatMap(\.leaves) }

    /// Case, whole-word and regex search over every text file; an open buffer contributes its in-memory text.
    /// Runs off the main actor. A newer search cancels this one: nil then.
    public func search(_ query: String, options: SearchOptions) async -> SearchOutcome? {
        searchTask?.cancel()
        latestSearch += 1
        let id = latestSearch
        let task = Task { await ProjectSearch.run(searchSources(), query: query, options: options) }
        searchTask = task
        let outcome = await task.value
        return id == latestSearch ? outcome : nil
    }

    private func searchSources() -> [SearchSource] {
        allFiles.filter { FileKind.isText($0.raw) }.map { f in
            buffers[f].map { SearchSource.text(f, $0.storage.string) } ?? .disk(f, url(for: f))
        }
    }

    /// `search` for the assistant's tool: it neither cancels nor is cancelled by the user's own search.
    public func searchForAssistant(_ query: String) async -> SearchOutcome? {
        await ProjectSearch.run(searchSources(), query: query, options: SearchOptions())
    }

    public func reveal(_ hit: SearchHit) { show(hit.file, range: hit.range, flash: true) }

    /// Entries of every `.bib` and hayagriva `.yml` file; an open buffer's unsaved text wins over disk.
    public func references() async -> [BibFile] {
        let sources = allFiles.filter { BibliographyFile.isBibliography($0.raw) }.map { f in
            buffers[f].map { SearchSource.text(f, $0.storage.string) } ?? .disk(f, url(for: f))
        }
        return await Self.parseBibliographies(sources)
    }

    @concurrent private static func parseBibliographies(_ sources: [SearchSource]) async -> [BibFile] {
        sources.compactMap { source in
            switch source {
            case .text(let f, let t): return BibliographyFile.parse(f, text: t)
            case .disk(let f, let url):
                guard let t = try? String(contentsOf: url, encoding: .utf8) else { return BibFile(id: f, entries: [], error: "The file is not readable text.") }
                return BibliographyFile.parse(f, text: t)
            }
        }
    }

    private func handle(_ e: EngineEvent) {
        eventTap?(e)
        switch e {
        case .status(let s):
            status = s
        case .compiled(let r):
            let previous = result?.seq ?? Seq(raw: 0)
            let previousMain = result?.main
            guard r.serial >= (result?.serial ?? 0) else { return }     // seq alone cannot order the compiles around a main switch
            result = r
            if r.snapshot.pageCount > 0 { lastGood = r; countWords(r.snapshot) }
            if let g = lastGood, g.seq >= staleSince { staleRoots = [] }     // the outline is the older of the two, so it decides
            trimLog()
            preview.show(r.snapshot)
            if r.seq > previous || r.main != previousMain { syncPreview(.resync) }     // settle() and the event stream may both deliver one result
            scheduleLint()
            scheduleInlayHints()
        case .diverged(let files):
            for f in files {
                guard let b = buffers[f] else { continue }
                resyncCount += 1
                engine.send(.setText(f, b.storage.string, takeSeq()))
            }
        }
    }

    /// The log keeps every edit newer than the oldest of: the latest result, the active list, the lint and inlay hints, and any
    /// request still in flight (its list will be mapped from the seq it was asked at).
    func trimLog() {
        guard let r = result else { return }
        log.trim(through: ([r.seq, lastGood?.seq, activeList?.seq, lint?.seq, inlay?.seq].compactMap { $0 } + inflightRequests).min()!)
    }

    /// Sends one request and waits for its reply. The log stays pinned from before the send until this returns,
    /// and the caller maps the answer through it in the same synchronous turn, before any trim can run.
    func ask<A: Sendable>(_ make: (@escaping @Sendable (A?) -> Void) -> EngineMessage) async -> A? {
        let asked = lastRecordedSeq
        inflightRequests.append(asked)
        let answer: A? = await withCheckedContinuation { c in engine.send(make { c.resume(returning: $0) }) }
        inflightRequests.remove(at: inflightRequests.firstIndex(of: asked)!)
        return answer
    }

    /// Asks the engine for completions at `cursor` (UTF-16) of the current text. Never blocks typing: the
    /// request is queued synchronously, so it sees exactly the edits recorded before this call.
    /// Nil when nothing completes, a newer request superseded this one, or the engine could not answer.
    /// The newest request's outcome replaces the active list.
    public func complete(in file: RelPath, at cursor: Int, explicit: Bool) async -> CompletionList? {
        latestRequest += 1
        let id = latestRequest
        let answer = await ask { reply in .complete(CompletionRequest(file: file, cursor: cursor, explicit: explicit, reply: reply)) }
        defer { trimLog() }
        guard id == latestRequest else { return nil }
        guard let a = answer, !a.items.isEmpty else { activeList = nil; return nil }
        let items = await enrichedWithBibliography(a.items)
        guard id == latestRequest else { return nil }
        let list = CompletionList(file: file, from: a.from, seq: a.seq, items: items)
        activeList = list
        return list
    }

    /// Completions for `text` standing in for `file` (UTF-16 `cursor`), e.g. a table cell spliced into its file. Side-effect free:
    /// the editor's active list and request counter stay untouched. Bibliography items are enriched like the editor's.
    public func complete(text: String, in file: RelPath, at cursor: Int, explicit: Bool = false) async -> CompletionList? {
        let answer = await ask { reply in .complete(CompletionRequest(file: file, cursor: cursor, explicit: explicit, text: text, reply: reply)) }
        defer { trimLog() }
        guard let a = answer, !a.items.isEmpty else { return nil }
        return CompletionList(file: file, from: a.from, seq: a.seq, items: await enrichedWithBibliography(a.items))
    }

    /// Every font family the engine's font book knows, spelled as `font:` matches it: the completions inside `font: ""`.
    /// `file` stands in as the host file of the probe; empty when the engine cannot answer.
    public func fontFamilyNames(host file: RelPath) async -> [String] {
        let probe = "#set text(font: \"\")"
        let list = await complete(text: probe, in: file, at: (probe as NSString).length - 2, explicit: true)
        // The labels are the quoted string literals.
        return list?.items.filter { $0.kind == .font }.map { $0.label.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) } ?? []
    }

    /// A click on page `page` (0-based) at `point` (pt from the page's top left) of the shown document.
    /// A project file opens with the caret at the mapped offset and a flash request; a position aims the
    /// preview; a web or mail URL is returned for the app to open. Package files and misses do nothing.
    public func click(page: Int, at point: CGPoint) async -> URL? {
        guard let shown = preview.pages.first?.snapshot else { return nil }    // every page shares the snapshot
        latestClickRequest += 1
        let id = latestClickRequest
        let answer = await ask { reply in .click(ClickRequest(shown: shown, page: page, point: point, reply: reply)) }
        defer { trimLog() }
        guard id == latestClickRequest, let a = answer, let target = a.target else { return nil }
        switch target {
        case .file(let path, let offset):
            guard let r = log.map(NSRange(location: offset, length: 0), in: path, from: a.seq),
                  buffers[path] != nil || exists(path) else { return nil }      // a reply for a path that moved meanwhile is dropped
            selectedFile = path
            guard let b = try? await open(path) else { return nil }
            b.requestSelection(r, flash: true)
            selectionRequests += 1
        case .position(let p):
            preview.aim(p, syncDecision(.navigation, userScrolled: false))
        case .url(let u):
            return ["http", "https", "mailto"].contains(u.scheme?.lowercased() ?? "") ? u : nil
        }
        return nil
    }

    /// Tooltip and diagnostics for the character at `cursor` (UTF-16) of the current text. Diagnostics
    /// whose range contains the cursor come first, so an error underline answers even without a tooltip.
    /// With `equation`, `range` is the whole formula (the card stays while the pointer is inside it); the crop
    /// exists only while the file is unchanged since the last successful compile.
    /// Nil when nothing applies, a newer hover superseded this one, the engine could not answer, or an
    /// edit touched the hovered leaf while the request was in flight.
    public func hover(in file: RelPath, at cursor: Int, pixelsPerPoint: Float = 3) async -> HoverInfo? {
        latestHoverRequest += 1
        let id = latestHoverRequest
        let answer = await ask { reply in .hover(HoverRequest(file: file, cursor: cursor, pixelsPerPoint: pixelsPerPoint, reply: reply)) }
        defer { trimLog() }
        guard id == latestHoverRequest, let a = answer, buffers[file] != nil else { return nil }
        let hits = diagnostics(in: file).filter { d in
            guard case .project(let l) = d.origin else { return false }
            return NSLocationInRange(cursor, l.range) || (l.range.length == 0 && l.range.location == cursor)
        }
        var range = hits.compactMap { d -> NSRange? in if case .project(let l) = d.origin { l.range } else { nil } }.first
        var tooltip: Tooltip?
        if let t = a.tip, let r = log.map(t.range, in: file, from: a.seq) {
            range = r
            tooltip = t.isCode ? .code(HoverText.code(t.text)) : .text(HoverText.markdown(t.text))
        }
        var equation: EquationImage?
        if let e = a.equation, let r = log.map(e.range, in: file, from: a.seq) {
            range = r
            equation = EquationImage(image: e.image, size: e.size)
            tooltip = nil       // the formula is the answer; typst-ide's symbol listing below it is noise
        }
        guard let range, tooltip != nil || !hits.isEmpty || equation != nil else { return nil }
        return HoverInfo(range: range, diagnostics: hits, tooltip: tooltip, equation: equation)
    }

    /// Reports the caret of `file` (the selected one) after a selection change with length 0. The reason
    /// comes from the buffer: an edit since the last report means typing, otherwise navigation.
    /// `programmatic` is the app saying it moved the caret itself (reveal, click-to-jump, completion).
    public func cursorMoved(in file: RelPath, to cursor: Int, programmatic: Bool = false) {
        guard let b = buffers[file] else { return }
        let edited = cursorSeqs.updateValue(b.lastSeq, forKey: file).map { $0 != b.lastSeq } ?? false
        lastCursor = (file, cursor)
        let um = b.undoManager
        let reason: SyncReason = programmatic || um.isUndoing || um.isRedoing ? .programmatic : edited ? .typing : .navigation
        syncPreview(reason)
    }

    private func syncPreview(_ reason: SyncReason) {
        guard preview.followsCursor, let (file, cursor) = lastCursor, file == activeFile else { return }
        let d = syncDecision(reason, userScrolled: preview.userScrolled)
        guard d.request else { return }
        latestCursorRequest += 1
        let id = latestCursorRequest
        Task {
            let answer = await ask { reply in .cursor(CursorRequest(file: file, cursor: cursor, reply: reply)) }
            trimLog()
            guard id == latestCursorRequest, let p = answer?.positions.first else { return }
            preview.aim(p, d)
        }
    }

    /// The list narrowed to what is typed in `[from, caret)` now, with the range a pick replaces.
    /// Nil if the list is no longer the active one, another file is showing, an edit touched the text
    /// before `from`, the caret left the range, or nothing matches.
    public func live(_ list: CompletionList, caret: Int) -> (range: NSRange, items: [CompletionItem])? {
        guard let active = activeList, active.file == list.file, active.seq == list.seq, activeFile == list.file,
              let storage = buffers[list.file]?.storage else { return nil }
        // Map the character before `from` instead of `from` itself: an insertion at `from` is typed
        // text that belongs to the range, not an edit before it.
        var from = 0
        if list.from > 0 {
            guard let m = log.map(NSRange(location: list.from - 1, length: 1), in: list.file, from: list.seq) else { return nil }
            from = m.location + 1
        }
        guard caret >= from, caret <= storage.length else { return nil }
        let range = NSRange(location: from, length: caret - from)
        let items = list.filtered(by: (storage.string as NSString).substring(with: range))
        return items.isEmpty ? nil : (range, items)
    }

    /// Dismiss: drops the active list so the log can trim again.
    public func endCompletion() {
        activeList = nil
        trimLog()
    }

    func scheduleAutosave() {
        autosave?.cancel()
        guard let delay = autosaveDelay, autosavePauses == 0 else { return }
        autosave = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            try? await saveAll()
        }
    }

    @concurrent private static func write(_ data: Data, to url: URL) async throws {
        try data.write(to: url, options: .atomic)
    }

    /// Cmd-S and autosave (1.5 s after the last edit). Text is copied on main; the atomic write runs
    /// off-main; saves are serialized, never parallel. The save task retains `self`, so closing the
    /// window cannot free the Project mid-write.
    public func saveAll() async throws(ProjectError) { try await save(under: nil) }

    /// `saveAll` for the buffers at or under `root` (all when nil).
    /// Waits until no save is running. A finished save task stays in `saving` until its own caller resumes on the
    /// main actor to clear it, and awaiting a finished task does not suspend: a bare `while let s = saving { await s.value }`
    /// spun forever on main and starved that caller (saving, compiling and completion froze). A save that is still
    /// in `saving` after its value arrived is done, so stop there.
    func waitForSaves() async {
        while let s = saving {
            await s.value
            if saving == s { return }
        }
    }

    func save(under scope: RelPath?) async throws(ProjectError) {
        await waitForSaves()
        let work = buffers.values.filter { $0.isDirty && (scope.map($0.path.isAtOrUnder) ?? true) && isOnDisk($0.path) && !changedOnDisk.contains($0.path) && reloadHolds[$0.path] == nil }.map { ($0, $0.lastSeq, $0.storage.string, $0.path) }
        let settings = self.textFileSettings()
        let root = root
        let job = Task { () -> ProjectError? in
            for (b, seq, text, path) in work {
                let (data, format) = TextFile.encode(text, format: b.fileFormat, settings: settings)
                do { try await Self.write(data, to: root.appending(path: path.raw)) } catch { return .writeFailed(path, error) }
                b.fileFormat = format
                b.savedSeq = seq
                self.diskHashes[path] = text.hashValue
                self.identify(path)       // the atomic write replaced the file: it has a new identity
            }
            return nil
        }
        let mine = Task { _ = await job.value }
        saving = mine
        let err = await job.value
        if saving == mine { saving = nil }       // a waiter may already have started the next save
        dirtyRevision += 1
        hasUnsavedChanges = buffers.values.contains(where: \.isDirty)
        if case .writeFailed(let path, let cause)? = err {
            saveError = "\(path.raw): \((cause as NSError).localizedDescription)"
        } else if err == nil {
            saveError = nil
            if !work.isEmpty { snapshotIfDue() }
            if !compilesWhileTyping { engine.send(.recompile) }
        }
        if let err { throw err }
    }

    /// A sidebar click: opens the file, and when the preview is unlocked a `.typ` file also becomes the previewed document.
    public func select(_ path: RelPath) {
        recordVisit(NavPlace(file: path))
        selectedFile = path
        if !previewLocked, FileKind.isTypst(path.raw) { setMain(path) }
    }

    /// Back/forward over the places `show` and `select` went to (the jump bar's chevrons).
    public private(set) var navigationHistory = NavigationHistory()
    private var traversing = false

    private func recordVisit(_ place: NavPlace) {
        guard !traversing else { return }
        navigationHistory.record(from: selectedFile, to: place, text: buffers[place.file]?.storage.string)
    }

    public func goBack() { if let p = navigationHistory.back() { traverse(p) } }
    public func goForward() { if let p = navigationHistory.forward() { traverse(p) } }

    private func traverse(_ place: NavPlace) {
        traversing = true
        defer { traversing = false }
        if let offset = place.offset { show(place.file, range: NSRange(location: offset, length: 0)) } else { selectedFile = place.file }
    }

    /// A sidebar double click: the file opens as a permanent tab.
    public func openPermanently(_ path: RelPath) {
        if navigate(to: path, permanent: true) { select(path); tabs.makePermanent(path) }
    }

    /// Removes the tab; when it was the shown file, the next tab (or nothing) is shown. The buffer stays open.
    public func closeTab(_ path: RelPath) {
        let next = tabs.close(path, active: selectedFile)
        if selectedFile != next { selectedFile = next }
    }

    public func makeTabPermanent(_ path: RelPath) { tabs.makePermanent(path) }

    public func togglePinTab(_ path: RelPath) {
        if tabs.pinned.contains(path) { tabs.unpin(path) } else { tabs.pin(path) }
    }

    public func closeOtherTabs(_ keep: RelPath) {
        for p in tabs.paths where p != keep { _ = tabs.close(p, active: keep) }
        if selectedFile != keep { selectedFile = keep }
    }

    public func setMain(_ path: RelPath) {
        guard path != main else { return }
        main = path
        engine.send(.setMain(path))
        recents?.setMain(path, for: id)
    }

    /// Words the author wrote in the document the preview shows (main file and its includes, prose only; see
    /// SourceWords), counted after each successful compile in the background.
    public private(set) var wordCount = 0
    /// Words per heading section of the same document, updated together with `wordCount`.
    public private(set) var sectionWords: [SectionWords] = []
    @ObservationIgnored private var wordsPending: Snapshot?
    @ObservationIgnored var wordsTask: Task<Void, Never>?

    /// Counts off the compile path. One worker; while it runs only the newest snapshot is kept, and a result
    /// is published only if nothing newer arrived meanwhile.
    private func countWords(_ s: Snapshot) {
        wordsPending = s
        guard wordsTask == nil else { return }
        wordsTask = Task {
            while let next = wordsPending {
                wordsPending = nil
                let pages = await next.sectionWords()
                let sources = Dictionary(textSources { FileKind.isTypst($0) }.compactMap(\.loaded).map { ($0.file, $0.text) }, uniquingKeysWith: { a, _ in a })
                let main = self.main
                let counted = await Task.detached(priority: .utility) { SourceWords.count(main: main, text: sources) }.value
                // Pages come from the compiled document's sections where they line up (same heading in the same place).
                let sections = counted.enumerated().map { i, s in
                    SectionWords(title: s.title, level: s.level, words: s.words,
                                 page: pages.indices.contains(i) && pages[i].title == s.title ? pages[i].page : pages.last { $0.title == s.title }?.page ?? 0)
                }
                if wordsPending == nil { wordCount = sections.reduce(0) { $0 + $1.words }; sectionWords = sections }
            }
            wordsTask = nil
        }
    }

    /// Waits for a compile covering every edit so far, and applies it like any delivered result.
    func settle() async -> CompileResult? {
        guard let r = await engine.flush() else { return nil }
        handle(.compiled(r))
        return r
    }

    /// Waits for a compile covering every edit so far (e.g. a divergence resync); throws if there is no page to export.
    func settledSnapshot() async throws(ProjectError) -> Snapshot {
        let covered = lastRecordedSeq
        guard let r = await settle(), r.seq >= covered else { throw .stale }
        if r.snapshot.pageCount == 0 { throw .compileFailed(r.snapshot.diagnostics) }
        return r.snapshot
    }

    /// Pages an export would produce, after waiting for the settled compile.
    public func exportPageCount() async throws(ProjectError) -> Int { try await settledSnapshot().pageCount }

    /// Renders the PDF off-main.
    public func exportPDF(standard: PDFStandard = .plain) async throws(ProjectError) -> Data {
        try await settledSnapshot().pdf(standard: standard).get()
    }

    /// One file's data per page, in page order.
    public func exportPages(_ format: PageFormat) async throws(ProjectError) -> [Data] {
        let s = try await settledSnapshot()
        var out: [Data] = []
        for page in 0..<s.pageCount {
            let data = switch format {
            case .png(let ppi): await s.png(page: page, ppi: ppi)
            case .svg: await s.svg(page: page)
            }
            guard let data else { throw .exportFailed("Page \(page + 1) could not be rendered.") }
            out.append(data)
        }
        return out
    }
}
