import AppKit
import SwiftUI
import TypoKit
import TypstEngine

extension SettingsKey {
    static let typewriter = "typewriterScrolling"
}

extension FocusedValues {
    @Entry var editorLayout: EditorLayout?
}

/// One window's editor arrangement (design/14e): Focus Mode and the split editor.
@MainActor @Observable final class EditorLayout {
    /// The second editor pane, right of the first. It never shows the first pane's file: one text storage
    /// cannot back two text views.
    var split = false
    /// The Open Quickly (⇧⌘O, ⌘T) or Go to Line (⌘L) panel is showing; nil while closed.
    var quickOpen: QuickOpenMode?
    /// The library (⇧⌘L) or command palette (⇧⌘P) is showing on this tab; nil while closed.
    var library: LibraryKind?
    var secondFile: RelPath? { didSet { if let f = secondFile { tabs.show(f, permanent: false, pinning: NavigationSettings.current.pinTabs) } } }
    /// The second pane's tabs (design/14h), derived from `secondFile` like the first pane's.
    var tabs = TabList()
    /// The second pane's caret per file; the first pane keeps its own on the buffer.
    @ObservationIgnored var secondCarets: [ObjectIdentifier: NSRange] = [:]
    /// Dimming of the unfocused pane: which pane last had keyboard focus, and the two panes' text views.
    @ObservationIgnored var secondFocused = false
    @ObservationIgnored weak var firstText: NSView?
    @ObservationIgnored weak var secondText: NSView?

    /// A `.bib` file shows as BibTeX text instead of the entry form.
    var bibSource = false

    /// The Issues / Compile Log area under the editor (⇧⌘Y).
    let bottom = BottomAreaModel()

    /// Focus Mode: no sidebar, preview or second pane; the text sits in a centered column.
    private(set) var focus = false
    var columns: NavigationSplitViewVisibility = .automatic
    /// The toolbar's preview toggle; the pop-out hides the pane independently.
    var showPreview = true
    /// The inspector column (⌥⌘0), remembered across launches. It closes when the window gets too narrow for it.
    var showInspector = UserDefaults.standard.bool(forKey: "inspector.shown") { didSet { UserDefaults.standard.set(showInspector, forKey: "inspector.shown") } }
    /// Too narrow a window hides the inspector without forgetting that it is on; it comes back when there is room.
    var inspectorFits = true
    func collapseInspector(forWidth width: CGFloat) {
        let fits = width >= 840 + (columns == .detailOnly ? 0 : 300)
        if fits != inspectorFits { inspectorFits = fits }
    }
    @ObservationIgnored private var columnsBeforeFocus: NavigationSplitViewVisibility = .automatic

    func toggleSplit(in project: Project) {
        split.toggle()
        if split { ensureSecondFile(in: project) }
    }

    func ensureSecondFile(in project: Project) {
        let options = Self.secondFiles(project)
        if secondFile.map({ !options.contains($0) }) ?? true { secondFile = options.first }
    }

    /// The text files the second pane may show: all but the first pane's.
    static func secondFiles(_ project: Project) -> [RelPath] {
        project.allFiles.filter { FileKind.isText($0.raw) && $0 != project.selectedFile }
    }

    /// A jump or click opened the second pane's file in the first: the panes trade files.
    func firstFileChanged(from old: RelPath?, to new: RelPath?) {
        if new != nil, new == secondFile { secondFile = old }
    }

    /// Shows `f` in the second pane; the file the first pane shows is traded instead (one file per pane).
    func showSecond(_ f: RelPath, in project: Project) {
        if f == project.selectedFile { project.selectedFile = secondFile } else { secondFile = f }
    }

    func closeSecondTab(_ f: RelPath, in project: Project) {
        let next = tabs.close(f, active: secondFile)
        if secondFile != next { secondFile = next == project.selectedFile ? nil : next }
    }

    func toggleFocus() {
        focus.toggle()
        if focus {
            columnsBeforeFocus = columns
            columns = .detailOnly
        } else {
            columns = columnsBeforeFocus
        }
    }
}

/// The split editor's second pane: a header with a file popup and a close button over its own editor.
struct SecondEditorPane: View {
    let project: Project
    let tables: TableEditing
    let actions: EditorActions
    let layout: EditorLayout
    @AppStorage(SettingsKey.editorTheme) private var theme = "default"
    @AppStorage(SettingsKey.inlineIssues) private var inlineIssues = true
    /// The last buffer this pane showed, kept on screen while a newly picked file is still being read,
    /// so the editor is not swapped for the empty state and rebuilt for that moment.
    @State private var held: Buffer?

    /// The hidden pane (split closed or Focus Mode) is no view at all: a hidden hosting view still answered
    /// accessibility hit tests, so its "Close Split Editor" button sat under the first pane's "+".
    var body: some View {
        if layout.split && !layout.focus { pane } else { Color.clear }
    }

    private var pane: some View {
        let file = layout.secondFile == project.selectedFile ? nil : layout.secondFile
        let bar = EditorTabBar(tabs: layout.tabs, active: file, project: project, focused: layout.secondFocused,
                         select: { layout.showSecond($0, in: project) }, makePermanent: { layout.tabs.makePermanent($0) },
                         togglePin: { layout.tabs.pinned.contains($0) ? layout.tabs.unpin($0) : layout.tabs.pin($0) },
                         close: { layout.closeSecondTab($0, in: project) },
                         closeOthers: { keep in
                            layout.tabs.paths.filter { $0 != keep }.forEach { _ = layout.tabs.close($0, active: keep) }
                            layout.showSecond(keep, in: project)
                         }) {
            GlassCluster {
                Menu {
                    ForEach(EditorLayout.secondFiles(project), id: \.self) { f in Button(f.raw, systemImage: "doc") { layout.secondFile = f } }
                } label: { Label("Open File", systemImage: "plus") }
                    .menuStyle(.button)
                    .menuIndicator(.hidden)
                    .help("Open a file in this pane")
                Button("Close Split Editor", systemImage: "xmark") { layout.split = false }
                    .help("Close the second editor (⌃⌘T)")
            }
            .labelStyle(.iconOnly)
        }
        let loaded = file.flatMap(project.buffer(for:))
        let content = Group {
            if let buffer = loaded ?? (file != nil ? held : nil) {
                EditorView(project: project, buffer: buffer, tables: tables, actions: actions, marks: project.lintHints(in: buffer.path) + (inlineIssues ? project.diagnostics(in: buffer.path) : []),
                           revealToken: 0, layout: layout, readOnly: LicenseStore.shared.readOnly, isPrimary: false)
                    .onDisappear { if project.focusedEditorFile == buffer.path { project.focusedEditorFile = nil; layout.secondFocused = false; layout.updateDimming() } }
            } else {
                ContentUnavailableView("No Other Text File", systemImage: "doc.text")
                    .foregroundStyle(Color(EditorTheme.named(theme).colors.ruler))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        return content.safeAreaInset(edge: .top, spacing: 0) { bar }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(EditorTheme.named(theme).colors.background))
        .task(id: layout.split) { if layout.split { layout.ensureSecondFile(in: project) } }
        .task(id: file) { if let file, (try? await project.open(file)) == nil { held = nil } }
        .onChange(of: loaded, initial: true) { _, b in if let b { held = b } }
        .onChange(of: project.dirtyRevision) { if let file, project.buffer(for: file)?.isDirty == true { layout.tabs.makePermanent(file) } }
    }
}

extension EditorView.Coordinator {
    /// The Format menu, the bottom bar and table and citation insertion act on the editor with keyboard focus.
    /// Until one has had it, the first pane does.
    func claimEditorIfUnset() {
        guard isPrimary, tables?.editor == nil || actions?.editor == nil else { return }
        tables?.editor = self
        actions?.editor = self
    }

    /// Deferred: inside becomeFirstResponder the window has not switched its first responder yet.
    func focusChanged() {
        Task { [weak self] in
            guard let self, let tv = textView, tv.window?.firstResponder === tv else { return }
            tables?.editor = self
            actions?.editor = self
            project?.focusedEditorFile = isPrimary ? nil : buffer?.path
            layout?.secondFocused = !isPrimary
            layout?.updateDimming()
        }
    }

    /// Only the editor the preview follows reports its caret: the first pane, or the second while it has focus.
    var reportsCursor: Bool { isPrimary || (buffer?.path).map { project?.focusedEditorFile == $0 } == true }

    func remember(_ sel: NSRange) {
        if isPrimary { buffer?.selection = sel } else if let buffer { layout?.secondCarets[ObjectIdentifier(buffer)] = sel }
    }

    /// The caret to restore when `b` is shown, clamped to its text.
    func savedSelection(of b: Buffer) -> NSRange {
        guard !isPrimary, let r = layout?.secondCarets[ObjectIdentifier(b)] else { return b.restoredSelection }
        let loc = min(r.location, b.storage.length)
        return NSRange(location: loc, length: min(r.length, b.storage.length - loc))
    }

    /// The character at the top of the visible text and its distance from that edge: Focus Mode
    /// rewraps the text, and this keeps the reading position instead of the scroll offset (see AnchoredScrollView).
    func readingAnchor(in scroll: NSScrollView) -> (index: Int, offset: CGFloat)? {
        guard let tv = textView, let tlm = tv.textLayoutManager, let tcm = tlm.textContentManager else { return nil }
        let top = scroll.contentView.bounds.minY
        let y = max(0, top - tv.textContainerOrigin.y)
        guard let frag = tlm.textLayoutFragment(for: CGPoint(x: 0, y: y)) else { return nil }
        let base = tcm.offset(from: tcm.documentRange.location, to: frag.rangeInElement.location)
        let line = frag.textLineFragments.first { frag.layoutFragmentFrame.minY + $0.typographicBounds.maxY > y } ?? frag.textLineFragments.first
        guard let line else { return nil }
        let lineTop = frag.layoutFragmentFrame.minY + line.typographicBounds.minY + tv.textContainerOrigin.y
        return (base + line.characterRange.location, lineTop - top)
    }

    /// Scrolls so the anchor's line sits at the same distance below the visible top as before the relayout.
    func restore(_ anchor: (index: Int, offset: CGFloat), in scroll: NSScrollView) {
        guard let tv = textView, let tlm = tv.textLayoutManager, let tcm = tlm.textContentManager,
              let loc = tcm.location(tcm.documentRange.location, offsetBy: anchor.index) else { return }
        scroll.layoutSubtreeIfNeeded()
        // A fragment laid out before the relayout keeps its stale origin, and a lone ensureLayout trusts estimated heights above:
        // lay out the prefix, then take the anchor's y from the end of the fragment before it.
        guard let prefix = NSTextRange(location: tcm.documentRange.location, end: loc) else { return }
        tlm.ensureLayout(for: prefix)
        var frag: NSTextLayoutFragment?, fragY: CGFloat = 0, end: CGFloat = 0
        tlm.enumerateTextLayoutFragments(from: tcm.documentRange.location, options: [.ensuresLayout]) { f in
            frag = f; fragY = end; end = f.layoutFragmentFrame.maxY
            return f.rangeInElement.endLocation.compare(loc) != .orderedDescending
        }
        guard let frag else { return }
        let local = anchor.index - tcm.offset(from: tcm.documentRange.location, to: frag.rangeInElement.location)
        let line = frag.textLineFragments.first { NSLocationInRange(local, $0.characterRange) } ?? frag.textLineFragments.first
        let lineTop = fragY + (line?.typographicBounds.minY ?? 0) + tv.textContainerOrigin.y
        tv.layoutSubtreeIfNeeded()
        let clip = scroll.contentView
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: max(0, lineTop - anchor.offset)))
        scroll.reflectScrolledClipView(clip)
    }

    /// Characters per line of the Focus Mode column.
    private static let column = 72

    func applyFocus(_ on: Bool, typewriter: Bool, to tv: NSTextView, in scroll: NSScrollView) {
        let gutter = !on && DisplaySettings.gutter
        if scroll.rulersVisible != gutter { (scroll as? AnchoredScrollView)?.holdAnchor(); scroll.rulersVisible = gutter }
        fitColumn(on, typewriter: typewriter)
        (scroll as? AnchoredScrollView)?.settleAnchor()
    }

    /// The centered column in Focus Mode (recomputed on every resize), the usual margins otherwise. Typewriter
    /// scrolling adds half a screen above and below so the first and last lines can sit in the middle too.
    func fitColumn(_ on: Bool? = nil, typewriter: Bool? = nil) {
        guard let tv = textView, let scroll = tv.enclosingScrollView else { return }
        var inset = NSSize(width: 4, height: 8)
        if on ?? (layout?.focus == true) {
            let char = ("0" as NSString).size(withAttributes: [.font: Highlighter.baseFont]).width
            let width = CGFloat(Self.column) * char + 2 * (tv.textContainer?.lineFragmentPadding ?? 0)
            inset.width = max(4, floor((scroll.contentView.bounds.width - width) / 2))   // without wrapping the text view is as wide as its text
            if typewriter ?? UserDefaults.standard.bool(forKey: SettingsKey.typewriter) {
                inset.height = max(8, floor(scroll.contentView.bounds.height / 2))
            }
        }
        if tv.textContainerInset != inset {
            (scroll as? AnchoredScrollView)?.holdAnchor()
            tv.textContainerInset = inset
            (scroll as? AnchoredScrollView)?.settleAnchor()
        }
    }

    /// Esc leaves Focus Mode; Option-Esc and F5 still complete.
    func exitFocusOnCancel(_ selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)), let layout, layout.focus else { return false }
        layout.toggleFocus()
        return true
    }

    /// Typewriter scrolling: while typing or moving with the keyboard in Focus Mode, the caret line stays centered.
    func typewriterScroll() {
        guard layout?.focus == true, UserDefaults.standard.bool(forKey: SettingsKey.typewriter), NSApp.currentEvent?.type == .keyDown,
              let tv = textView, let window = tv.window, let scroll = tv.enclosingScrollView, tv.selectedRange().length == 0 else { return }
        let caret = tv.convert(window.convertFromScreen(tv.firstRect(forCharacterRange: tv.selectedRange(), actualRange: nil)), from: nil)
        let clip = scroll.contentView
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: max(0, caret.midY - clip.bounds.height / 2)))
        scroll.reflectScrolledClipView(clip)
    }
}

/// Keeps the reading position across every change of the editor's width (Focus Mode, sidebar, split, preview,
/// window resize): the clip keeps its pixel offset while the text rewraps, so the top line would drift.
/// The anchor is taken while the old layout is valid and restored once the width has stopped changing.
final class AnchoredScrollView: NSScrollView {
    weak var editor: EditorView.Coordinator?
    var minimap: MinimapView?
    private var held: (index: Int, offset: CGFloat)?

    /// The minimap takes its width at the right edge, outside the clip view.
    override func tile() {
        super.tile()
        minimap?.place(in: self)
    }
    private var generation = 0

    override func setFrameSize(_ size: NSSize) {
        if size.width != frame.width { holdAnchor() }
        super.setFrameSize(size)
        if held != nil { settleAnchor() }
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        releaseAnchor()
    }

    /// Takes the anchor unless one is already held (before the width or the insets change).
    func holdAnchor() {
        guard held == nil, window != nil, let editor else { return }
        held = editor.readingAnchor(in: self)
    }

    /// Restores on the next run-loop turn, pushed back while more frame changes arrive; a live resize waits for its end.
    func settleAnchor() {
        guard held != nil, !inLiveResize else { return }
        generation += 1
        let g = generation
        DispatchQueue.main.async { [weak self] in if let self, g == self.generation { self.releaseAnchor() } }
    }

    private func releaseAnchor() {
        guard let a = held, let editor else { return }
        held = nil
        editor.restore(a, in: self)
    }
}
