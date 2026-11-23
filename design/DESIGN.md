# Typst editor skeleton: design (synthesized)

Base: the opus candidate. Grafts and rejections are recorded in RATIONALE.md under "Synthesis decision". Deployment targets: macOS 27 and iOS 27. The app target builds for macOS now; the iPad target comes later on the same `TypoKit`.

One idea carries the design. Every text mutation in every open file passes through one funnel, the `NSTextStorage` delegate of that file's `Buffer`. The funnel stamps it with a project-wide sequence number and appends it to a lock-protected FIFO that a single compile thread drains. Text truth, edit order, coalescing, and result staleness all derive from that one sequence number.

## 1. Usage (caller's view)

The app target sees `TypoKit` only. It never sees a C type, a JSON string, or a thread.

```swift
import SwiftUI
import TypoKit

@main
struct TypoApp: App {
    @State private var recents = RecentProjects()            // bookmarks + Open Recent, one store
    init() { TypstRuntime.warmUp() }                        // starts the font index load off-main

    var body: some Scene {
        // One window per project. Equal ProjectID values refocus the existing window.
        // SwiftUI encodes the ProjectID for window restoration.
        WindowGroup(for: ProjectID.self) { $id in
            if let id { ProjectWindow(id: id) } else { WelcomeView() }
        }
        .environment(recents)
        .commands { ProjectCommands() }                     // Open…, Open Recent, Save, Export PDF
    }
}

struct ProjectWindow: View {
    let id: ProjectID
    @Environment(RecentProjects.self) private var recents
    @State private var project: Project?
    var body: some View {
        Group { if let project { ProjectView(project: project) } else { ProgressView() } }
            .task(id: id) { project = try? await Project.open(id, recents: recents) }   // TODO: error alert
        .focusedSceneValue(\.project, project)               // Cmd-S and Export target the key window
    }
}

struct ProjectView: View {
    @Bindable var project: Project
    var body: some View {
        NavigationSplitView {
            FileSidebar(nodes: project.files, selection: $project.selectedFile)
        } content: {
            if let buffer = project.selectedBuffer {
                EditorView(buffer: buffer, marks: project.diagnostics(in: buffer.path))
            }
        } detail: {
            PreviewView(preview: project.preview)
        }
        .inspector(isPresented: .constant(true)) {
            DiagnosticsList(project.diagnostics) { project.reveal($0) }
        }
        .toolbar { CompileStatusBadge(status: project.status) }
    }
}
```

Three call sites the app writes, and nothing more of the engine:

```swift
// Sidebar click: opening a file creates its Buffer once, seeded from disk.
project.selectedFile = RelPath("chapters/intro.typ")       // didSet: await open(path) if not yet open

// Diagnostic click: switches file and selects the range valid for the CURRENT text.
project.reveal(diagnostic)                                  // no-op for package/detached diagnostics

// Export: waits until the compile covers every edit made so far, then writes PDF bytes.
let pdf: Data = try await project.exportPDF()              // throws .compileFailed([Diagnostic])
```

The macOS editor wraps `NSTextView` and swaps the storage per file:

```swift
#if os(macOS)
struct EditorView: NSViewRepresentable {
    let buffer: Buffer
    let marks: [Diagnostic]
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let tv = scroll.documentView as! NSTextView
        if tv.textContentStorage?.textStorage !== buffer.storage {
            tv.textContentStorage?.textStorage = buffer.storage   // TextKit 2, one storage per file
        }
        // TODO: diff `marks` into NSTextLayoutManager rendering attributes (squiggles).
        //       Rendering attributes are not storage edits: no undo entry, no engine message.
        if let range = buffer.takePendingSelection() { tv.setSelectedRange(range); tv.scrollRangeToVisible(range) }
    }
    // Coordinator: NSTextViewDelegate.undoManager(for:) returns buffer.undoManager (per-file undo).
}
#endif
```

The preview renders lazily. A page view exists only while it is near the viewport, and its task id is the content hash:

```swift
struct PageView: View {
    let page: PageInfo
    let preview: PreviewModel
    @Environment(\.displayScale) private var displayScale
    var body: some View {
        let key = ImageKey(page.hash, pixelsPerPoint: displayScale * preview.zoom)
        PageImage(preview.image(for: key))                   // sync cache lookup, no view-local image state
            .aspectRatio(page.size, contentMode: .fit)
            .task(id: key) { await preview.render(page, key) } // restarts only when the hash or scale changes
    }
}
```

## 2. Module map

| Target | Kind | Platforms | Contents | Imports |
|---|---|---|---|---|
| `TypstBridge` | binaryTarget (XCFramework) | macOS, iOS, iOS sim | Rust staticlib + `typst_bridge.h` + modulemap | nothing |
| `TypstEngine` | Swift library in `Packages/Typo` | macOS 27, iOS 27 | the bridge wrapper, the engine actor, runtime, fonts, packages, and the plain data types they return | `internal import TypstBridge`, Foundation, Synchronization, CoreGraphics |
| `TypoKit` | Swift library in `Packages/Typo` | macOS 27, iOS 27 | the rest of section 4: `Project`, `Buffer`, editor logic, tables, bibliography, git, export, the project tools | `TypstEngine`, Foundation, Observation, Synchronization, CoreGraphics, CoreText, AppKit or UIKit (for `NSTextStorage` only) |
| `JSONRPC`, `ACPProtocol`, `MCPProtocol` | Swift libraries in `Packages/Typo` | macOS 27 | the JSON-RPC line protocol, and the ACP client and MCP server protocols on it, without Typo types | `JSONRPC` |
| `TypoAssistant`, `TypoACP`, `TypoMCP` | Swift libraries in `Packages/Typo` | macOS 27 | the assistant; agents over ACP; the `typo-mcp` server's tools | `TypoKit`; `TypoAssistant` + `ACPProtocol`; `TypoKit` + `MCPProtocol` |
| `Typo` | app target, generated by `xcodegen` from `project.yml` | macOS 27 now, iPad later | SwiftUI scenes and views; `EditorView` behind `#if os(macOS)`; `NSOpenPanel` folder grant; sandbox entitlements (user-selected read-write, app-scope bookmarks, network client) | the libraries above |

`internal import TypstBridge` (SE-0409) makes every `Tb*` type unreachable from the app. An import of the bridge from the app target fails the build. The iPad app adds a `UITextView` `EditorView` and a `.fileImporter` open flow. `TypoKit` does not change.

Core files, all in one flat folder: `Bridge.swift` (the only file touching `Tb*`), `Runtime.swift`, `Engine.swift`, `Project.swift`, `Buffer.swift`, `EditLog.swift`, `Diagnostic.swift`, `Preview.swift`, `Access.swift`, `Highlighter.swift`.

## 3. C ABI (`typst_bridge.h`)

Three handles, and one thread rule per handle. All strings in both directions are pointer and length UTF-8, never NUL-terminated. No JSON.

```c
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

typedef struct { const uint8_t *ptr; size_t len; } TbStr;   // borrowed UTF-8
typedef struct { uint8_t *ptr; size_t len; } TbBytes;       // Rust-owned; release with tb_bytes_free

typedef struct TbRuntime  TbRuntime;   // process-wide: font store + package cache dir. Immutable, Sync.
typedef struct TbWorld    TbWorld;     // one per project. Send, not Sync: one thread at a time.
typedef struct TbSnapshot TbSnapshot;  // one compile's output. Immutable, Sync: any thread, concurrently.

// Runtime. Reads font_index_path (FontInfo keyed by path+size+mtime), re-reads only changed or new
// font files, rewrites the index. ~2 s on the very first launch, a stat pass afterwards.
// Embedded fonts (Libertinus, New CM, DejaVu Mono) are always included.
TbRuntime *tb_runtime_new(const TbStr *font_paths, size_t font_path_count,
                          TbStr font_index_path, TbStr package_cache_dir);
void tb_runtime_free(TbRuntime *);                       // only after every world is freed

// World. Overlay files (open editor buffers) are served from memory and NEVER read from disk;
// every other project file is read from disk under root_dir; packages come from the cache or
// are downloaded inside compile. on_download runs on the compiling thread before each download.
typedef void (*TbDownloadFn)(void *ctx, TbStr package_spec);
TbWorld *tb_world_new(const TbRuntime *, TbStr root_dir, TbStr main_path,
                      TbDownloadFn on_download, void *ctx);   // NULL if main_path is not a valid vpath
void tb_world_set_main(TbWorld *, TbStr path);
void tb_world_set_text(TbWorld *, TbStr path, TbStr text);   // create or replace an overlay (idempotent)
// Applies one edit to an overlay in UTF-16 units of its pre-edit text. Returns false and changes
// nothing if the path has no overlay, the range is out of bounds or splits a scalar, or the
// post-edit UTF-16 length != expected_len. false means the mirror diverged: caller resyncs.
bool tb_world_edit(TbWorld *, TbStr path, uint32_t utf16_start, uint32_t utf16_end,
                   TbStr replacement, uint32_t expected_len);
// Compiles. Never NULL. Owns the comemo eviction policy (see below); nothing else evicts.
// Runs inside stacker::grow (32 MB), because the Swift side calls it on a GCD thread (512 KB stack)
// and typst layout recursion is not stack-guarded (only typst-eval uses stacker).
TbSnapshot *tb_world_compile(TbWorld *);
void tb_world_free(TbWorld *);

// Snapshot. page_count == 0 means the compile failed (diagnostics explain why).
typedef struct { uint64_t hash_hi, hash_lo; float width_pt, height_pt; } TbPage;  // hash128(&Page)
enum { TB_ERROR = 0, TB_WARNING = 1 };
enum { TB_DETACHED = 0, TB_PROJECT = 1, TB_PACKAGE = 2 };
typedef struct {
    uint8_t severity, origin;
    TbStr path;                         // project-relative, or "@ns/name:ver/file" for packages
    uint32_t utf16_start, utf16_end;    // in the text this compile saw (the overlay or the disk file)
    TbStr message;
    TbStr hints;                        // '\n'-joined
} TbDiagnostic;                         // strings borrowed from the snapshot
uint32_t     tb_snapshot_page_count(const TbSnapshot *);
TbPage       tb_snapshot_page(const TbSnapshot *, uint32_t index);
uint32_t     tb_snapshot_diagnostic_count(const TbSnapshot *);
TbDiagnostic tb_snapshot_diagnostic(const TbSnapshot *, uint32_t index);
// Premultiplied RGBA8, width*height*4 bytes. ptr NULL if index is out of range.
TbBytes tb_snapshot_render(const TbSnapshot *, uint32_t page, float pixel_per_pt,
                           uint32_t *width, uint32_t *height);
TbBytes tb_snapshot_pdf(const TbSnapshot *);             // ptr NULL if no document or export error
void    tb_snapshot_free(TbSnapshot *);
void    tb_bytes_free(TbBytes);
```

Rust side, in prose:
- `TbRuntime` holds `Arc<FontStore>`. Every world shares one `FontBook`, so the comemo cache is shared across windows too.
- `TbWorld` holds `overlays: HashMap<FileId, Source>`. `World::source` and `World::file` check `overlays` first and fall back to `FileStore`. `edit` uses `Source::edit` with `Lines::utf16_to_byte`, then checks `lines().len_utf16() == expected_len`.
- Eviction lives inside `tb_world_compile` and nowhere else. `static COMPILES: AtomicU64` and `static LIVE_WORLDS: AtomicUsize` are maintained by `tb_world_new` and `tb_world_free`. After each compile, call `comemo::evict(10 * max(1, LIVE_WORLDS))`. Each world's entries then survive about 10 of its own compiles while windows take turns. There is no `tb_evict`, so no second owner can exist.
- Verified in source: `FontSource: Send + Sync + Any` (typst-kit fonts.rs:100) and slots use `OnceLock`, so `Arc<FontStore>` is shared safely. `FontInfo` derives `Serialize, Deserialize` (typst-library text/font/info.rs:12), so the font index is a JSON file of `(path, size, mtime, [(index, FontInfo)])`. `comemo::evict` takes per-cache `RwLock` write locks, so it is safe while another world compiles.
- `TbSnapshot` is `{ doc: Option<PagedDocument>, pages: Vec<TbPage>, diags: Vec<OwnedDiag> }`. Diagnostic ranges are converted to UTF-16 while the world still has the exact `Source` the compile saw.
- `TbDownloadFn` is fired by a `Downloader` wrapper around `SystemDownloader`. The packages store lives in the world, and the cache dir comes from the runtime.

## 4. Swift type sketch (`TypoKit`)

### Identity, access, recents (`Access.swift`)

```swift
/// Project-relative path ("chapters/intro.typ"). The only file identity in the app and in the ABI.
/// Validated once at construction: '/'-separated, no leading '/', no '..', no empty components.
public struct RelPath: Hashable, Sendable, Codable { public let raw: String; public init?(_ raw: String) { fatalError("not implemented") } }

/// Stable window identity. SwiftUI stores it for restoration and refocuses equal values.
public struct ProjectID: Hashable, Sendable, Codable { let uuid: UUID }

/// The single owner of bookmarks and of the Open Recent list. Persisted in UserDefaults.
@MainActor @Observable public final class RecentProjects {
    struct Record: Codable { let id: ProjectID; var bookmark: Data; var main: RelPath; var name: String; var lastOpened: Date }
    public private(set) var records: [Record] = []           // most recent first, capped at 20

    /// Picked URL (folder or .typ file) -> ProjectID. Reuses the ID when the resolved root path
    /// already has a record, so reopening a folder refocuses its window.
    /// The macOS bookmark uses .withSecurityScope and iOS uses []. This is the only platform branch.
    /// A lone .typ file grants only that file in the sandbox. The caller (open flow in the app) then shows
    /// a second folder panel pre-pointed at the parent; `root` is always a granted folder. If the user
    /// declines, root is the parent anyway and sibling imports fail as ordinary diagnostics.
    public func register(root: URL, main: RelPath) throws -> ProjectID { fatalError("not implemented") }
    public func setMain(_ main: RelPath, for id: ProjectID) { fatalError("not implemented") }
    func record(_ id: ProjectID) -> Record? { fatalError("not implemented") }
    func refreshBookmark(_ id: ProjectID, root: URL) { fatalError("not implemented") }   // when stale
}

/// Holds security-scoped access to the project root for exactly as long as the Project lives.
/// Rust reads disk files with plain POSIX calls under this process-wide grant.
final class ScopedAccess: Sendable {
    let root: URL
    init(resolving bookmark: Data) throws(ProjectError) { fatalError("not implemented") }  // start…
    deinit { /* root.stopAccessingSecurityScopedResource() */ }
}
```

### Runtime (`Runtime.swift`)

```swift
/// Process-wide, loaded once. Fonts are ready before any world exists, so the FontBook never changes
/// under a live world.
public final class TypstRuntime: @unchecked Sendable {   // handle immutable; TbRuntime is Sync
    public static func warmUp() { _ = shared }
    static let shared: Task<TypstRuntime, Never> = Task.detached(priority: .userInitiated) { TypstRuntime() }

    let handle: OpaquePointer                                // TbRuntime*
    private init() {
        // urls  = CTFontCollectionCreateFromAvailableFonts -> kCTFontURLAttribute (same code on iOS)
        //         Unreadable paths (sandbox, font managers) are skipped; the rest of the index stays valid.
        // Runs on a DispatchQueue, not Task.detached: it blocks ~2 s on first launch.
        // index = URL.cachesDirectory/typst/font-index.json
        // pkgs  = URL.applicationSupportDirectory/typst/packages  (not Caches: the system may purge Caches,
        //         and offline compiles need the packages; excluded from backup)
        fatalError("not implemented")
    }
}
```

### Edits and the log (`EditLog.swift`)

```swift
/// Monotonic across all files of one project. Edit n happened after every edit < n.
public struct Seq: Comparable, Hashable, Sendable { let raw: UInt64 }

/// One mutation of one file, in UTF-16 units of the pre-edit text.
struct Edit: Sendable {
    let seq: Seq
    let file: RelPath
    let range: NSRange          // pre-edit range that was replaced
    let replacement: String
    let newLength: Int          // file's UTF-16 length after the edit (mirror integrity check)
}

/// Edits newer than the latest delivered compile. Lives on the main actor in Project.
struct EditLog {
    private(set) var entries: [Edit] = []
    mutating func append(_ e: Edit) { entries.append(e) }
    mutating func trim(through seq: Seq) { entries.removeAll { $0.seq <= seq } }

    /// Maps a range computed at `seq` into the current text of `file`. Pure.
    /// An edit wholly before shifts the range. An edit wholly after leaves it. Overlap -> nil.
    /// Unit-tested with insert-before, insert-at-start, delete-across, other-file, and emoji cases.
    func map(_ range: NSRange, in file: RelPath, from seq: Seq) -> NSRange? { fatalError("not implemented") }
}
```

### Buffer (`Buffer.swift`)

```swift
/// One open file. Its NSTextStorage is the single source of truth for that file's text.
/// The engine overlay is a mirror fed only by this delegate, and disk is a copy written by save.
@MainActor public final class Buffer: NSObject, NSTextStorageDelegate {
    public let path: RelPath
    public let storage: NSTextStorage
    public let undoManager = UndoManager()                    // per file, survives file switches
    var savedSeq: Seq                                         // seq of the text last written to disk
    var lastSeq: Seq                                          // seq of the latest edit to this file
    public var isDirty: Bool { lastSeq != savedSeq }
    private var pendingSelection: NSRange?
    unowned let project: Project

    init(path: RelPath, text: String, seq: Seq, project: Project) { fatalError("not implemented") }

    /// The funnel. Typing, paste, undo/redo, spell-correction, and find/replace all end here.
    nonisolated func textStorage(_ s: NSTextStorage, didProcessEditing mask: NSTextStorageEditActions,
                                 range: NSRange, changeInLength delta: Int) {
        // guard mask.contains(.editedCharacters) else { return }   // attribute-only: highlighter, marks
        // MainActor.assumeIsolated {
        //   let pre = NSRange(location: range.location, length: range.length - delta)
        //   project.record(path, pre, s.attributedSubstring(from: range).string, newLength: s.length)
        // }
        // Grouped edits (beginEditing…endEditing) arrive as one union range, which is still exact.
    }
    nonisolated func textStorage(_ s: NSTextStorage, willProcessEditing mask: NSTextStorageEditActions,
                                 range: NSRange, changeInLength delta: Int) {
        // Highlighter.apply(s, editedRange: range)   // seam; attributes only
    }

    func requestSelection(_ r: NSRange) { pendingSelection = r }
    public func takePendingSelection() -> NSRange? { defer { pendingSelection = nil }; return pendingSelection }
}

/// Syntax highlighting seam. Stub today; later typst-syntax via a tb_highlight call.
enum Highlighter { static func apply(_ s: NSTextStorage, editedRange: NSRange) {} }
```

### Engine (`Engine.swift`)

```swift
enum EngineMessage: Sendable {
    case setText(RelPath, String, Seq)    // open or resync a buffer
    case edit(Edit)
    case setMain(RelPath)
}

enum EngineEvent: Sendable {
    case status(CompileStatus)
    case compiled(CompileResult)
    case diverged(Set<RelPath>)           // tb_world_edit returned false: resend full text
}

/// Owns the TbWorld. Runs on its own serial queue, so a 2 s package download blocks that queue
/// and never a cooperative-pool thread. One Engine per project.
actor Engine {
    private let queue: DispatchSerialQueue
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    private let world: OpaquePointer                         // TbWorld*, touched only on `queue`
    private let inbox = Mutex(Inbox())                       // FIFO, the only cross-thread state
    private struct Inbox { var messages: [EngineMessage] = []; var drainScheduled = false }
    private var appliedSeq = Seq(raw: 0)
    private var diverged: Set<RelPath> = []
    private var latest: CompileResult?
    nonisolated let events: AsyncStream<EngineEvent>
    private nonisolated let sink: AsyncStream<EngineEvent>.Continuation

    init(runtime: TypstRuntime, root: URL, main: RelPath) throws(ProjectError) { fatalError("not implemented") }

    /// Synchronous and non-blocking from the main actor: lock, append, maybe schedule one drain.
    /// FIFO order is the lock order, which is the order of the caller's calls.
    nonisolated func send(_ m: EngineMessage) {
        // let schedule = inbox.withLock { $0.messages.append(m); defer { $0.drainScheduled = true }; return !$0.drainScheduled }
        // if schedule { Task { await self.drain() } }
    }

    /// Coalescing loop. Takes everything queued, applies it in order, compiles once, and repeats until
    /// the inbox is empty. Ten keystrokes during one compile become one compile, and none is dropped.
    private func drain() {
        // while let batch = inbox.withLock({ s in s.messages.isEmpty ? { s.drainScheduled = false; return nil }() : s.messages.take() }) {
        //   for m in batch { apply(m) }   // edit failure marks the file diverged; later edits to it are skipped until its setText
        //   if !diverged.isEmpty { sink.yield(.diverged(diverged)); continue }   // never compile a wrong mirror
        //   sink.yield(.status(.compiling))
        //   latest = CompileResult(Snapshot(tb_world_compile(world)), seq: appliedSeq)
        //   sink.yield(.compiled(latest!)); sink.yield(.status(.idle))
        // }
    }

    /// Drains now and returns the result that covers every message sent before this call.
    func flush() -> CompileResult? { drain(); return latest }

    // on_download trampoline: sink.yield(.status(.downloading(spec)))   (runs on `queue`)
}
```

### Results, diagnostics, pages (`Diagnostic.swift`, `Bridge.swift`)

```swift
public enum CompileStatus: Sendable, Equatable { case idle, compiling, downloading(package: String) }

public struct Location: Hashable, Sendable { public let file: RelPath; public let range: NSRange }

public struct Diagnostic: Identifiable, Sendable {
    public enum Severity: Sendable { case error, warning }
    public enum Origin: Sendable { case project(Location), package(String), detached }
    public let id: Int
    public let severity: Severity
    public let message: String
    public let hints: [String]
    public let origin: Origin
}

/// Everything one compile produced, stamped with the last edit it saw.
struct CompileResult: Sendable {
    let seq: Seq                          // covers every edit <= seq, in every file
    let snapshot: Snapshot
}

public struct PageInfo: Identifiable, Sendable {
    public let id: Int                    // page index
    public let hash: UInt128              // content identity; equal hash = identical pixels
    public let size: CGSize               // points
    let snapshot: Snapshot
}

/// Wraps TbSnapshot. Copies pages and diagnostics into Swift values at init and frees on deinit.
/// Rendering and PDF run on the global executor, concurrently with the next compile.
final class Snapshot: @unchecked Sendable {      // handle immutable; TbSnapshot is Sync
    let pages: [PageInfo]                 // empty when the compile failed
    let diagnostics: [Diagnostic]         // ranges valid at CompileResult.seq
    private let handle: OpaquePointer     // TbSnapshot*
    init(_ handle: OpaquePointer) { fatalError("not implemented") }
    deinit { /* tb_snapshot_free(handle) */ }

    /// Zero copy: CGDataProvider's info pointer holds only the TbBytes, and its release callback calls
    /// tb_bytes_free. The image must NOT retain the Snapshot: hash-keyed images outlive many compiles,
    /// and each would otherwise pin a whole PagedDocument.
    @concurrent func render(page: Int, pixelsPerPoint: Float) async -> CGImage? { fatalError("not implemented") }
    @concurrent func pdf() async -> Data? { fatalError("not implemented") }
}
```

### Preview (`Preview.swift`)

```swift
public struct ImageKey: Hashable, Sendable {
    public let hash: UInt128
    public let pixelsPerPoint: Float      // displayScale * zoom, rounded to 1/8
}

/// Shows the latest successful document. A failed compile changes diagnostics, not pages.
@MainActor @Observable public final class PreviewModel {
    public private(set) var pages: [PageInfo] = []
    public var zoom: CGFloat = 1
    private var cache = ImageLRU(byteLimit: 256 << 20)       // 128 MB on iOS
    private var inFlight: Set<ImageKey> = []
    private let renderSlots = RenderSlots(limit: 2)           // at most 2 renders at once; flinging through 150 pages stays bounded

    /// Also drops every cached key whose hash is not in the new page set. Without this, a reflowing
    /// page inserts ~8 MB per keystroke and LRU pressure evicts unchanged visible pages, whose
    /// task(id:) never fires again. An undo that brings a hash back costs one ~8 ms render.
    func show(_ s: Snapshot) {
        // guard !s.pages.isEmpty else { return }
        // pages = s.pages; cache.retain(hashes: Set(s.pages.map(\.hash)))
        fatalError("not implemented")
    }
    public func image(for key: ImageKey) -> CGImage? { cache[key] }
    /// Called from PageView.task(id:). A cache hit returns at once, so pages whose hash survived the
    /// edit never re-render.
    public func render(_ page: PageInfo, _ key: ImageKey) async {
        // if cache[key] != nil { cache.touch(key); return }
        // guard inFlight.insert(key).inserted else { return }
        // defer { inFlight.remove(key) }
        // await renderSlots.acquire(); defer { renderSlots.release() }
        // guard !Task.isCancelled else { return }               // view scrolled away while waiting
        // if let img = await page.snapshot.render(page: page.id, pixelsPerPoint: key.pixelsPerPoint) { cache.insert(img, for: key) }
    }
}

/// Byte-bounded LRU. Cost = width*height*4. Main actor only, so no lock. Recency is refreshed by
/// `touch` (called from `render` on a hit, i.e. each time a page view appears), never by the
/// subscript, which SwiftUI calls during body evaluation. Eviction then hits scrolled-away pages.
struct ImageLRU { init(byteLimit: Int) { fatalError("not implemented") }
    subscript(key: ImageKey) -> CGImage? { fatalError("not implemented") }
    mutating func touch(_ key: ImageKey) { fatalError("not implemented") }
    mutating func retain(hashes: Set<UInt128>) { fatalError("not implemented") }
    mutating func insert(_ image: CGImage, for key: ImageKey) { fatalError("not implemented") }
    mutating func removeAll() { fatalError("not implemented") }         // memory warning
}
```

### Project (`Project.swift`)

```swift
public enum ProjectError: Error { case accessDenied, mainFileMissing(RelPath), unreadable(RelPath), compileFailed([Diagnostic]), stale, writeFailed(RelPath, any Error) }

public struct FileNode: Identifiable, Sendable { public let id: RelPath; public let isDirectory: Bool; public let children: [FileNode]? }

/// One per window. Owns the buffers, the edit log, the latest result, and the save schedule.
@MainActor @Observable public final class Project {
    public let id: ProjectID
    public private(set) var files: [FileNode]
    public private(set) var main: RelPath
    public var selectedFile: RelPath? { didSet { /* Task { try await open(selectedFile) } */ } }
    public var selectedBuffer: Buffer? { selectedFile.flatMap { buffers[$0] } }
    public private(set) var status: CompileStatus = .idle
    public let preview = PreviewModel()

    private var buffers: [RelPath: Buffer] = [:]             // opened on demand, kept until the window closes
    private var opening: [RelPath: Task<Buffer, any Error>] = [:]   // in-flight opens; see open(_:)
    private var nextSeq = Seq(raw: 1)
    private var log = EditLog()
    private var result: CompileResult?                       // latest delivered, never older than the previous one
    private let engine: Engine
    private let access: ScopedAccess
    private var autosave: Task<Void, Never>?

    public static func open(_ id: ProjectID, recents: RecentProjects) async throws(ProjectError) -> Project {
        // record -> ScopedAccess -> await TypstRuntime.shared.value -> Engine(root, main)
        // -> open(main) (sends .setText) -> files = await FileNode.scan(root) -> start consuming events
        fatalError("not implemented")
    }

    /// Reads the file off-main and creates its Buffer. The overlay is seeded with exactly that text.
    /// Idempotent, also under concurrency: a sidebar click and a reveal racing across the disk-read
    /// suspension both await the same `opening[path]` task, so one file never gets two storages.
    @discardableResult public func open(_ path: RelPath) async throws(ProjectError) -> Buffer {
        // if let b = buffers[path] { return b }
        // if let t = opening[path] { return try await t.value }
        // opening[path] = Task { text = read off-main; b = Buffer(path, text, seq: takeSeq())
        //                        engine.send(.setText(path, text, b.lastSeq)); buffers[path] = b; return b }
        // defer { opening[path] = nil }
        fatalError("not implemented")
    }

    /// Called only by Buffer's delegate. Order is the order of the calls: log, engine, autosave.
    func record(_ path: RelPath, _ pre: NSRange, _ text: String, newLength: Int) {
        // let e = Edit(seq: takeSeq(), file: path, range: pre, replacement: text, newLength: newLength)
        // buffers[path]!.lastSeq = e.seq; log.append(e); engine.send(.edit(e)); scheduleAutosave()
    }

    /// Derived, never stored: the latest result's diagnostics mapped through the edits it did not see.
    /// Marks, the list, and reveal all read this, so they always agree with the current text.
    /// A file unopened at compile time was read from disk; a Buffer opened later starts from that
    /// same text and logs only later edits, so the mapping stays exact.
    public var diagnostics: [Diagnostic] {
        // result?.snapshot.diagnostics.compactMap { d in
        //   guard case .project(let loc) = d.origin else { return d }
        //   return log.map(loc.range, in: loc.file, from: result!.seq).map { d.with(range: $0) }   // nil = edited away
        // } ?? []
        fatalError("not implemented")
    }
    public func diagnostics(in file: RelPath) -> [Diagnostic] { fatalError("not implemented") }

    public func reveal(_ d: Diagnostic) {
        // guard case .project(let loc) = d.origin else { return }
        // selectedFile = loc.file; Task { try await open(loc.file).requestSelection(loc.range) }
    }

    private func handle(_ e: EngineEvent) {
        // .status(s):       status = s
        // .compiled(r):     guard r.seq >= result?.seq else { return }; result = r; log.trim(through: r.seq); preview.show(r.snapshot)
        // .diverged(files): for f in files { engine.send(.setText(f, buffers[f]!.storage.string, takeSeq())) }
    }

    /// Cmd-S and autosave (1.5 s after the last edit, on scene background, on window close).
    /// Text is copied on main; the atomic write runs off-main; writes per file are chained, never parallel.
    /// The save task retains `self`, so closing the window cannot free the Project mid-write.
    /// Quit: while any buffer is dirty the Project holds ProcessInfo.disableSuddenTermination(), and
    /// the macOS app delegate's applicationShouldTerminate returns .terminateLater until every open
    /// Project's saveAll() finishes. No edit is lost on Cmd-Q.
    public func saveAll() async throws(ProjectError) { fatalError("not implemented") }

    public func setMain(_ path: RelPath) { /* main = path; engine.send(.setMain(path)); recents.setMain */ }

    /// Waits for a compile covering every edit so far, then renders the PDF off-main.
    public func exportPDF() async throws(ProjectError) -> Data {
        // guard let r = await engine.flush(), r.seq >= lastRecordedSeq else { throw .stale }   // e.g. diverged
        // if r.snapshot.pages.isEmpty { throw .compileFailed(r.snapshot.diagnostics) }
        // return await r.snapshot.pdf()!
        fatalError("not implemented")
    }
}
```

## 5. Syntax highlighting and prose-only spell check (added after the skeleton)

Problem: colors must follow every keystroke with no lag, also while a compile or a 2 s package download blocks the engine queue. So highlighting never goes through `Engine`.

Shape: each `Buffer` owns a second derived mirror next to the engine overlay, a `SyntaxMirror` wrapping a Rust `TbSyntax` (a bare `typst_syntax::Source`: no world, no fonts, no files). It lives on the main actor and is fed by the same storage-delegate funnel, with the same UTF-16 edit and length check as `tb_world_edit`. `Source::edit` reparses incrementally and returns the reparsed byte range; that range (in UTF-16) is the dirty range to recolor. The text owner is still only `NSTextStorage`; the mirror is derived, like the overlay.

```c
typedef struct TbSyntax TbSyntax;    // one per Buffer. Send, not Sync: main actor only.
typedef struct { uint32_t start, end; } TbRange16;          // UTF-16, half-open
typedef struct { uint32_t start, end; uint8_t tag; } TbSpan; // tag = typst_syntax::Tag as u8, stable order below

TbSyntax *tb_syntax_new(TbStr text);
void      tb_syntax_free(TbSyntax *);
// Same contract as tb_world_edit (pre-edit UTF-16 range, expected post-edit UTF-16 length).
// On success writes the reparsed range of the NEW text to *dirty and returns true.
// false: nothing changed; caller resets with tb_syntax_set_text and recolors everything.
bool      tb_syntax_edit(TbSyntax *, uint32_t start16, uint32_t end16, TbStr replacement,
                         uint32_t expected_len, TbRange16 *dirty);
void      tb_syntax_set_text(TbSyntax *, TbStr text);
// Highlighted leaves intersecting [start16, end16), document order. Writes at most cap spans,
// returns the total count (call again with a bigger buffer if total > cap).
size_t    tb_syntax_highlight(const TbSyntax *, uint32_t start16, uint32_t end16, TbSpan *out, size_t cap);
// Prose ranges intersecting [start16, end16): SyntaxKind::Text leaves whose parent is not Raw
// (Text inside Raw is code). Same count/cap convention.
size_t    tb_syntax_prose(const TbSyntax *, uint32_t start16, uint32_t end16, TbRange16 *out, size_t cap);
// What the caret at a UTF-16 position edits: 0 markup, 1 code, 2 math, 3 string/raw/comment text (section 8).
uint8_t   tb_syntax_mode(const TbSyntax *, uint32_t pos16);
```

Tag order (u8): Comment, Punctuation, Escape, Strong, Emph, Link, Raw, Label, Ref, Heading, ListMarker, ListTerm, MathDelimiter, MathOperator, MathGroupingParens, Keyword, Operator, Number, String, Function, Interpolated, Error (typst-syntax 0.15.1 highlight.rs:5). A Rust `const _` match keeps the order exhaustive so a new upstream tag fails the build.

Swift (`TypoKit`):
- `public enum SyntaxTag: UInt8, CaseIterable, Sendable` mirrors the order above.
- `Buffer` owns `syntax: SyntaxMirror` (internal). In the delegate, the character edit range and delta are captured BEFORE any attribute change, so the engine funnel never sees an attribute-inflated range. `willProcessEditing` only feeds the mirror (and remembers the dirty range); highlighting runs in `didProcessEditing`, before the engine funnel. Attribute writes made in `willProcessEditing` widen the edit and NSTextView then parks the caret at the end of the widened range (a typed character mid-paragraph jumped the caret to the paragraph end); in `didProcessEditing` they leave the selection alone and still reach layout within the same `processEditing`, so there is no stale-colour frame. Highlighting writes storage attributes (`.foregroundColor`, and a bold font for heading/strong) only inside the dirty range, after first resetting that range to the base attributes, so no stale color survives outside or inside it. Attribute-only edits never reach the engine (existing `.editedCharacters` filter) and never register undo.
- `Highlighter.theme: [SyntaxTag: Style]` with dynamic system colors (dark mode for free). Default theme lives in core; app themes later replace the table.
- `public func Buffer.proseRanges(in: NSRange) -> [NSRange]` for the spell-check filter.

App: `EditorView`'s text-view delegate implements `textView(_:didCheckTextIn:types:options:results:orthography:wordCount:)` and drops spelling/grammar results whose range is not inside a prose range. Diagnostic marks stay rendering attributes (section 1), so they never collide with highlight storage attributes.

Invariant tests: (1) after any edit sequence, spans from the incremental mirror equal spans from `tb_syntax_new(final text)`; (2) the storage's color attributes over the WHOLE text equal a full re-highlight of the final text (catches dirty-range bugs, e.g. typing `$` turns the rest of a paragraph into math, deleting it turns it back); (3) highlighting adds no engine edits (`resyncCount == 0`, compile count unchanged by attribute changes); (4) prose ranges include paragraph and heading words and exclude code, math, strings and raw.

## 6. Autocompletion (typst-ide)

Problem: `typst_ide::autocomplete` needs the whole world (library, fonts, packages, other files) and, for labels and citations, the last compiled document. The world lives on the engine queue, which can be busy with a compile (22 to 94 ms) or a package download. Typing must never wait, and the popup must keep up with a fast typist.

Shape:
- **Runs on the engine queue, ahead of compiles.** A completion request is an inbox message like an edit, so it sees exactly the edits sent before it. The drain loop applies the batch's edits in order, answers that batch's completion requests (only the newest per file; older ones get `nil`), and only then compiles. A request therefore waits at most for a compile that was already running. Requests go through the same synchronous `send` inside `withCheckedContinuation` (an actor-isolated call could land after later keystrokes and see the wrong text). Every continuation resumes exactly once: answered, superseded by a newer request for the same file (`nil`), file diverged so the batch does not compile (`nil`), path has no overlay (`nil`), engine closed with requests still queued (`nil`).
- **World additions (Rust):** `TbWorld` keeps `last_doc: Option<PagedDocument>` from the last successful compile and passes `last_doc.as_ref()` as `output` (`impl<T: Output> AsOutput for &T`, typst-library foundations/target.rs:59). `impl IdeWorld`: `upcast` returns self; `files()` lists project files under the root (skip hidden entries; shortcut: rescanned per request with a cap of 5000 entries, upgrade to a cached tree when projects get large); `packages()` stays empty for now (no `@preview/` name completion yet).
- **ABI:**
```c
typedef struct TbCompletions TbCompletions;
typedef struct { uint8_t kind; TbStr label; TbStr apply; TbStr detail; TbStr symbol; } TbCompletion; // strings borrowed until free; empty TbStr = absent
// typst_ide::autocomplete on overlay `path` at a UTF-16 cursor. NULL if the path has no overlay or the
// cursor is out of range or splits a surrogate. count == 0 means nothing to show.
TbCompletions *tb_world_complete(TbWorld *, TbStr path, uint32_t cursor16, bool explicit_);
uint32_t      tb_completions_from(const TbCompletions *);   // UTF-16 start of the replaced range [from, cursor)
uint32_t      tb_completions_count(const TbCompletions *);
TbCompletion  tb_completions_get(const TbCompletions *, uint32_t index);
void          tb_completions_free(TbCompletions *);
```
  Kind order (u8): Syntax, Func, Type, Param, Constant, Path, Package, Label, Font, Symbol (`Symbol` carries its glyph in `symbol`). Exhaustive match in Rust, like the highlight tags.
- **Swift (`TypoKit`):**
  - `public struct CompletionItem { kind: CompletionKind; label: String; apply: String?; detail: String? }`, `public enum CompletionKind` (the symbol case carries the glyph).
  - `public struct CompletionList { file: RelPath; from: Int; seq: Seq; items: [CompletionItem] }`.
  - `public func Project.complete(in file: RelPath, at cursor: Int, explicit: Bool) async -> CompletionList?`.
  - `public func Project.live(_ list: CompletionList, caret: Int) -> (range: NSRange, items: [CompletionItem])?` maps `from` through the `EditLog` from `list.seq` (the same machinery as diagnostics); nil if an edit touched text before `from`, the file differs, or the caret left the range. It filters by the text typed in `[from, caret)`: case-insensitive prefix matches first, then subsequence matches, each in typst-ide order. This lets the popup follow fast typing without a round trip per key. `Project` owns the single active completion list (set by `complete`, cleared on dismiss); the `EditLog` is trimmed only through `min(latest result seq, active list seq)`, so `live` always sees every edit made since its list, even when a compile lands in between.
  - `public struct Snippet { text: String; placeholders: [NSRange] }` with `static func parse(_ apply: String) -> Snippet`: `${}` is an empty tab stop, `${name}` and `${n:default}` insert `name` / `default`; a dollar sign not followed by `{` is literal; braces are literal. `placeholders` are in order of appearance.
- **App (`EditorView`):**
  - Triggers: after each single typed character (not paste, undo or programmatic edits) request implicitly when the character is one of `#` `.` `@` `<` `(` `,` `:` `"` `$` or a space, or when no popup is showing and the character is an identifier character; otherwise keep filtering the current list with `live`. Explicit: override `complete(_:)` without calling super. Stock NSTextView routes Esc (via `cancelOperation:`), Option-Esc and F5 there, so this covers all three and suppresses the dictionary word list. Ctrl-Space is the system input-source shortcut by default and is not advertised.
  - Popup: borderless non-activating child `NSPanel` with an `NSTableView` (SF Symbol per kind, the glyph for symbols, label, one-line secondary detail), at most 10 visible rows, under the caret line via `firstRect(forCharacterRange:)`, flipped above near the screen bottom, system materials and colors.
  - Keys via `textView(_:doCommandBy:)` while visible: up / down / page up / page down move, Return / Tab accept, Esc dismisses. Click accepts. Hide on caret leaving the range, file switch, scroll, focus or key-window loss.
  - Accept: `insertText(snippet.text, replacementRange: range)` (undoable, goes through the funnel), then select the first placeholder (or put the caret at the end). Tab and Shift-Tab then move between the call's arguments, which also reaches later placeholders (design/14i).

Tests: implicit `#te|` lists `text` with `from` right after `#`; math `$al|$` lists `alpha` as symbol `α`; `#include "|"` lists `kapitel.typ`; `@|` lists a label only after a successful compile; a request sent right after edits typing `#rec` (without awaiting a compile) lists `rect`, and its reply arrives before that batch's `.compiled` event; `Snippet.parse` cases (`rect(${})`, `let ${name} = ${value}`, a literal dollar around `${x}`, `${2:2}`, no placeholder); `live` filters on the typed prefix and returns nil after an edit before `from`.

## 7. Jump between preview and source (typst-ide)

Verified API (typst-ide 0.15.1 jump.rs): `jump_from_click<D: JumpFromDocument>(world: &dyn IdeWorld, document: &D, position: &D::Position) -> Option<Jump>` (line 34), `jump_from_cursor<D: JumpInDocument>(document: &D, source: &Source, cursor: usize) -> Vec<D::Position>` (line 343), both implemented for `PagedDocument`, whose position is `PagedPosition { page: NonZeroUsize /* 1-based */, point: Point /* pt from the page's top left */ }`. `Jump` is `File(FileId, usize /* byte offset */)`, `Url(Url)` or `Position(PagedPosition)`.

Shape:
- **Both directions run on the engine queue as inbox requests, exactly like completion** (section 6): they need `last_doc`, and click needs the world to resolve spans. Same rules: answered at their batch position before that batch's compile, newest request per kind wins (older resume `nil`), every continuation resumes exactly once, and replies carry the engine's `appliedSeq` so the main actor maps offsets through the `EditLog` (and pins the log while a request is in flight). Inference to be checked by the stale-click test: spans of unchanged nodes survive incremental reparses, so a document one compile old still resolves into the current text.
- **Trigger policy (decides whether this feels native or jittery):**
  - *Navigation*: a selection change with no edit (editor click, arrow keys, Cmd-arrows) syncs; the preview scrolls if the target is outside the visible rect and shows the marker.
  - *Typing and post-compile re-syncs*: scroll only if the target is outside the visible rect, never show the marker, and do not scroll at all if the user scrolled the preview manually since the last navigation sync.
  - *Programmatic selections* (reveal, click-to-jump, completion accept, undo/redo) do not sync at all.
  - `Buffer` knows whether a selection change came with an edit (`lastSeq` moved); the decision is a pure function in the core (`SyncReason` → scroll? marker?) and is unit-tested.
- **ABI:**
```c
typedef struct { uint32_t page; float x_pt, y_pt; } TbPosition;   // page 0-based here
enum { TB_JUMP_NONE = 0, TB_JUMP_FILE = 1, TB_JUMP_URL = 2, TB_JUMP_POSITION = 3 };
typedef struct TbJump TbJump;
// Click at a point (pt, top left origin) on page `page` of the last successful document. NULL if no document.
// Resolves against the snapshot the preview is showing (not last_doc), so the user maps exactly what they clicked.
TbJump    *tb_world_jump_from_click(TbWorld *, const TbSnapshot *shown, TbPosition click);
uint8_t    tb_jump_kind(const TbJump *);
TbStr      tb_jump_path(const TbJump *);       // FILE: project-relative path; empty for package files (treated as NONE by Swift)
uint32_t   tb_jump_offset16(const TbJump *);   // FILE: UTF-16 offset in the world's current text of that file
TbStr      tb_jump_url(const TbJump *);        // URL
TbPosition tb_jump_position(const TbJump *);   // POSITION
void       tb_jump_free(TbJump *);
// Positions in the last successful document that belong to the leaf at `cursor16` in overlay `path`.
// Writes at most cap, returns the total count (0 if no document, no overlay, or nothing found).
size_t     tb_world_jump_from_cursor(TbWorld *, TbStr path, uint32_t cursor16, TbPosition *out, size_t cap);
```
- **Swift (`TypoKit`):**
  - `public struct PreviewPosition: Equatable, Sendable { page: Int; point: CGPoint }` (0-based page, pt).
  - `public func Project.click(page: Int, at point: CGPoint) async -> URL?` performs the jump itself: a project file opens and the caret lands at the mapped offset (`reveal`-style pending selection with length 0, plus a flash request the editor shows with `showFindIndicator(for:)`); a position sets `preview.target`; a URL (http, https, mailto only) is returned for the app to open with `NSWorkspace`. Package files and misses do nothing.
  - `public func Project.cursorMoved(in file: RelPath, to cursor: Int)` sends a cursor-sync request when `followsCursor` is on; the reply sets `preview.target` to the first position. After every delivered compile result the project re-syncs the last known cursor of the selected file, because a new document can change where the cursor's text sits.
  - `PreviewModel.target: PreviewPosition?` (observable, set by the project, consumed by the view) and `PreviewModel.followsCursor: Bool` (persisted in UserDefaults, default on).
- **App:**
  - Preview: a click on a page converts the view location to page points (`location / displayedWidth * page.size.width`) and calls `project.click`; returned URLs open via `NSWorkspace.shared.open`. Cursor feedback: the arrow cursor over pages (no link affordance needed in v1).
  - When `preview.target` changes, the preview scrolls only if the target point is outside the visible rect (no scrolling while the cursor's text is already visible, so typing never jitters the preview), then shows a short-lived marker at the point (accent-colored, fades out in about one second).
  - Editor: `textViewDidChangeSelection` calls `project.cursorMoved` for selection changes with length 0, coalesced so a burst of moves sends one request (the engine already keeps only the newest).
  - View menu: "Preview Follows Cursor" toggle (bound to `followsCursor`).

Tests: round trip on the two-file fixture (for several cursor offsets in prose of both files, `click(jump_from_cursor(cursor))` lands inside the same leaf as the cursor, in the right file); a `#link("https://typst.app")[Typst]` click returns the URL; an outline-entry click returns a position on the heading's page; a click after uncompiled edits before the target maps to the same word in the current text; cursor sync on a heading in `kapitel.typ` returns its page; exactly-once resumption for superseded and diverged cases; timing (report only) for click and cursor sync on the 38-page sample.

## 8. Polish: window, save errors, find and replace, auto-closing pairs

- **Window:** project windows get `.defaultSize(width: 1280, height: 820)` and the sidebar a minimum column width so file names are not truncated. `.defaultSize` only applies when no saved frame exists.
- **Save errors are never silent.**
  - Autosave failure: no modal. `Project.saveError: String?` (observable) drives a "Couldn't save" toolbar state with the reason in its help text; the next successful save clears it.
  - Save on close or quit failure: the `Project` stays alive (the save task retains it) and an app-modal alert names the file and the error with "Retry" and "Discard Changes". Nothing is lost until the user picks Discard. SwiftUI's window delegate is not replaced.
- **Find and replace:** `usesFindBar = true`, incremental searching on, `TextEditingCommands()` in the scene so Cmd-F / Cmd-G / Cmd-Option-F reach the find bar. Replace All is one undo step and goes through the storage funnel like any edit.
- **Auto-closing pairs.** A pure decision in the core, `PairEdit.decide(typed:, text:, selection:, mode:, autoInserted:) -> PairAction`, unit-tested; the editor only executes the action.
  - Pairs: `(` `)`, `[` `]`, `{` `}` everywhere; `$` `$` in markup; `"` `"` only in code and math (in markup prose `"` becomes a smart quote and is not paired). Mode comes from the syntax mirror at the caret.
  - Insert the closer only when the next character is whitespace, a closer, or the end of the text (so `(` before `foo` gives `(foo`).
  - With a selection, an opener wraps the selection.
  - Opener and closer are one undo step.
  - Typing a closer steps over the next character only if that closer was auto-inserted and is still directly after the caret.
  - Backspace between an empty auto-inserted pair deletes both.
  - Never act while there is marked text (dead keys, IME), and never for programmatic inserts (completion accept, find/replace, undo/redo, paste).
  - Integration: `#include "` auto-closes to `#include "|"`, the path completion appears, and accepting it gives exactly `#include "kapitel.typ"`.

## 9. Hover info (typst-ide tooltip)

Verified API (typst-ide 0.15.1 tooltip.rs:24): `tooltip(world: &dyn IdeWorld, output: Option<impl AsOutput>, source: &Source, cursor: usize, side: Side) -> Option<Tooltip>`; `Tooltip::Text(EcoString)` is prose/Markdown (function and parameter docs via `docs.summary()`, label details, closure captures), `Tooltip::Code(EcoString)` is Typst code (values of expressions, e.g. `3` for `#x` after `#let x = 1 + 2`). Labels need the document. Trivia leaves give `None`.

Shape:
- **Engine request like click/cursor** (sections 6 and 7): `.hover(file, cursor16)`, newest wins, answered at batch position before the compile, exactly-once resumption, reply carries `appliedSeq`; log pinned while in flight.
- **ABI:**
```c
typedef struct TbHover TbHover;
enum { TB_HOVER_TEXT = 1, TB_HOVER_CODE = 2 };
// tooltip at a UTF-16 cursor (Side::After) in overlay `path`, using last_doc for labels.
// NULL if nothing to show (no overlay, bad cursor, trivia, no tooltip).
TbHover   *tb_world_hover(TbWorld *, TbStr path, uint32_t cursor16);
uint8_t    tb_hover_kind(const TbHover *);
TbStr      tb_hover_text(const TbHover *);
TbRange16  tb_hover_range(const TbHover *);   // UTF-16 range of the hovered leaf, for anchoring and staleness
void       tb_hover_free(TbHover *);
```
- **Swift (`TypoKit`):**
  - `public struct HoverInfo { range: NSRange; diagnostics: [Diagnostic]; tooltip: Tooltip? }` with `public enum Tooltip { case text(AttributedString), code(AttributedString) }`.
  - `public func Project.hover(in file: RelPath, at cursor: Int) async -> HoverInfo?`: asks the engine, maps the leaf range through the `EditLog` (nil if an edit touched it), and merges the current mapped diagnostics whose range contains the cursor (they come first). Diagnostics alone are enough to return a `HoverInfo` (hovering an error underline shows the message even without a tooltip).
  - Pure helpers, unit-tested: `HoverText.markdown(_:)` renders `Text` Markdown into an `AttributedString` (inline Markdown, paragraphs kept); link destinations that are not `http`, `https` or `mailto` (typst docs use internal `$func/...` style links) become plain text. `HoverText.code(_:)` renders `Code` monospaced and highlighted with the existing syntax mirror and `Highlighter.theme`.
- **App (`EditorView`):** a tracking area on the text view; after the mouse rests ~0.5 s over a character (no button down, no marked text, completion popup not showing), call `project.hover` with `characterIndexForInsertion`-style hit testing restricted to points actually over glyphs (no hover past line ends or in the margin). Show the result in a borderless non-activating child panel styled like the completion popup (system material, max width ~480 pt, scrolls if long), anchored below the hovered range (`firstRect(forCharacterRange:)`), flipped above near the screen bottom. Diagnostics shown first with the severity symbol, message and hints; then the tooltip. Hide when the mouse leaves the hovered range (with a small grace area towards the panel), on key down, scroll, file switch, window resign. Never steals focus.

Tests: `#text(fill: red)[Hi]` hovering `text` gives `.text` with a non-empty summary and a range covering exactly `text`; hovering `fill` gives the parameter docs; `#let x = 1 + 2` then `#x` gives `.code` containing `3`; `@intro` gives a label tooltip only after a successful compile; hovering inside an error's range returns that diagnostic first; a stale reply after an edit before the range maps the range, after an edit inside it returns nil; superseded and diverged requests resume nil; markdown helper turns `[text]($text)` into plain `text` and keeps `https` links; timing (report only) on the 38-page sample.

## 10. Package name completion (`@preview/...`)

Facts: typst-ide completes package specs inside `#import "@..."` / `#include "@..."` strings from `IdeWorld::packages() -> &[(PackageSpec, Option<EcoString>)]`, sorted by name with the newest version first and deduplicated per name unless versions are being completed (complete.rs:1143). The official index `https://packages.typst.org/preview/index.json` has 5256 entries for 1768 names (2026-11-17); fields include `name`, `version`, `description`, `compiler` (minimum compiler version), `keywords`. It is 2.5 MB raw, 285 KB compressed, served with an `etag` and `cache-control: max-age=600`.

Shape:
- **Fetching is never on the engine queue** (a download there would stall compiles). `TypstRuntime` owns a `PackageIndex` (Swift, Foundation only, so it works on iOS): on launch it loads the cached copy (`<package dir>/preview/index.json` plus its etag), then revalidates in the background with `URLSession` and `If-None-Match` at most once per hour; a 304 keeps the cache, a 200 replaces it atomically, any failure keeps whatever is cached (offline still completes from the cache; with no cache there are simply no package completions, no error UI).
- **Parsing and filtering in Rust:** `size_t tb_runtime_set_package_index(TbRuntime *, TbStr json)` parses the index with serde_json, drops entries whose `compiler` requirement is newer than the embedded typst (0.15.1) or that fail to parse, builds `(PackageSpec{namespace: "preview", name, version}, description)` and stores them as an `Arc<[...]>` behind a lock in the runtime; returns the number kept. Each `TbWorld` takes a fresh `Arc` clone at the start of every request, so `IdeWorld::packages()` can return a plain slice.
- **No new completion UI:** the existing popup shows them with the package symbol and the description as the one-line detail; `live` filtering already handles typing after `"@`. Triggers already include `"` and `@`, and auto-pairing gives `#import "@|"`.

Tests: a fixture index with three packages, one requiring compiler 99.0.0 and one with two versions, gives completions at `#import "@|"` with only compatible packages, the newest compatible version per name, and descriptions in `detail`; `PackageIndex` loads from cache, skips revalidation when fresh, keeps the cache on a network failure and on a 304, replaces it on a 200 (fetcher injected, no real network in tests); accepting `cetz` after `#import "@ce` with an auto-paired quote gives exactly `#import "@preview/cetz:<version>"`; timing (report only) of `tb_runtime_set_package_index` on a saved copy of the real index.

## 11. Tables: insert and edit visually

User choice (2026-11-17): "Tabelle einfügen" and "Tabellen-Editor"; pasting from Numbers/Excel was not chosen.

### Insert
- Format menu "Insert Table…" and a toolbar button open a popover with a Pages-style grid picker (hover selects up to 10 × 8; click inserts) and two toggles, "Header row" (default on) and "As figure with caption" (default on).
- Code generation is a pure core function `TableCode.insert(rows:columns:header:figure:) -> Snippet` (the `Snippet` type from section 6): one table row per line, two-space indent, `table.header(...)` for the first row when enabled, wrapped in `#figure(table(...), caption: [])` when enabled, otherwise `#table(...)`. Empty cells are placeholders, so the first cell is selected after insertion. It is inserted with `insertText(_:replacementRange:)` as one undo step, on its own lines (a newline is added before or after when the caret is mid-line).

### Edit
- **Find and parse in Rust with the real parser.** `TbTable *tb_syntax_table_at(const TbSyntax *, uint32_t cursor16)` finds the innermost `table(...)` or `grid(...)` call containing the cursor (with or without `#`, also inside `figure(...)`) and returns:
  - the call's UTF-16 range and callee (`table` or `grid`);
  - named args in source order, each `(name, value source text)`, kept verbatim;
  - the header: present or not, its own named args verbatim (e.g. `repeat: false`), its cells;
  - body cells in order, each as `(kind, source text, inner text)` where kind is `content` (a `[...]` block; inner text = the markup inside the brackets) or `expr` (any other expression; inner text = `#` + its source);
  - or an `unsupported` reason, for tables the editor cannot round-trip safely: spread args (`..`), `table.cell(...)` with `colspan`/`rowspan`, `table.hline`/`vline`/`footer`, a `columns:` value that is not an integer or an array literal, or a cell count that is not a multiple of the column count. The editor then explains the reason instead of opening.
  - Accessors follow the existing count/get style; strings are borrowed until `tb_table_free`.
- **Pure core model, unit-tested:** `TableModel { columns: [ColumnSpec], header: [Cell]?, rows: [[Cell]], callee, namedArgs, headerArgs, range }` with `Cell { original: String?, text: String }`; edits: set cell text, insert/delete/move row, insert/delete/move column, toggle header (first body row becomes the header and back), per-column alignment. `TableCode.render(_ model) -> String`:
  - an unchanged cell writes back its original source verbatim, so untouched cells are byte-identical;
  - a changed cell writes `[text]`, escaping unbalanced markup-level `[` `]` and a trailing backslash in markup so the block stays valid (brackets in raw, strings, comments and math are left as typed);
  - `columns:` keeps its form: an integer is updated; an array literal gets `auto` appended for a new column and the matching entry removed for a deleted one;
  - alignment writes `align: (left, center, right, ...)` and replaces an existing `align:` only if it was an array literal or a single alignment; any other `align:` (for example a function) disables the alignment controls;
  - every other named arg is written back verbatim in its original order;
  - layout: one table row per line, two-space indent, matching the insert format.
  - Applying an unchanged model is a no-op (no edit at all).
- **App:** Format menu "Edit Table…" and the editor's context menu, enabled when the caret is inside a supported table. A sheet on the project window shows a spreadsheet-like grid: one text field per cell with Tab / Shift-Tab / Return navigation, the header row visually distinct, a column header strip with alignment menus, and buttons or context menus for add, delete and move of rows and columns, plus the header toggle. "Done" applies the whole change as ONE undoable replacement of the call's range via `insertText(_:replacementRange:)` (so it goes through the funnel, highlighting and the engine like any edit); "Cancel" discards. Native SwiftUI controls and system colors.

Tests: the insert snippet for 3 × 2 with header and figure compiles without errors and selects the first cell; parse an existing table with header, `columns: (1fr, auto)`, `align: center`, a `stroke:` arg and a non-content cell (`image(...)` or a string); round trip without edits is a no-op; editing one cell changes only that cell's text in the output; add/delete/move row and column produce code that compiles and has the expected cell order (check via the engine's diagnostics being empty, and the PDF text order); header toggle; alignment; unbalanced bracket escaping; each unsupported case returns its reason; `grid(...)` works the same as `table(...)`; the applied edit is one undo step and the engine mirror stays exact.

## 12. Edist-level workspace UI

Source: the user's screenshots of Edist (2026-11-17) and "ich will das alles haben". Decisions taken without an answer from the user (they may override): the books tab is **References (.bib)**; the preview lock **pins the previewed document**.

### 12.1 Editor visuals (app only)
- **Current line:** the logical line containing the caret gets a light accent background across the full width (dynamic color, works in dark mode); its line number in the gutter is drawn in the primary label color, other numbers secondary. No highlight while text is selected.
- **Inline diagnostics:** a line with an error gets a light red background tint; at the right end of its first visual line a pill badge (rounded, system red fill, white semibold small text) shows the message, truncated to the available width; warnings use system orange. More than one diagnostic on a line: the first plus "+N". Clicking the pill shows the full message in the hover panel. Drawn as overlay decorations from the derived `project.diagnostics(in:)` (never storage attributes), repositioned on layout, scroll and resize. The existing squiggle stays.
- **Completion popup restyle:** rounded card; each row has a kind badge, a small rounded square in a kind color with a letter (F function, L label, P parameter, T type, C constant, K syntax/keyword, Pa path, Pk package, Fo font; symbols show their glyph instead); matched characters of the label in bold (from the same prefix/subsequence match `live` uses); a detail area under the list for the selected item (first sentence of its detail; label details show the label's content, e.g. "P = NP").
- **Rounded selection:** selection backgrounds are drawn as rounded rectangles (radius ~4, accent selection color, inactive color when the window is not key) behind the text, replacing NSTextView's square selection.
- **Animated caret:** a custom caret that glides to its new position (~80 ms ease-out) and blinks with the system timing; the system insertion indicator is hidden. Respects Reduce Motion (no glide) and the user's caret width/color. Behind a Settings toggle "Animated caret" (default on; this unit introduces the app's `Settings` scene). Public API only to hide the system indicator; with the toggle off the system caret is fully restored. Drop rule: if hiding needs private API, or marked text (dead keys, IME), dictation or VoiceOver caret tracking misbehave, the feature is dropped and reported, not worked around.
- **One decoration layer:** current line, rounded selection, inline diagnostic pills and the custom caret are drawn by a single decoration view behind/over the text as appropriate, recomputed from layout fragments on layout, scroll, selection and diagnostics changes, so they never drift or fight over z-order. Find-bar match highlights must stay visible above the custom selection.

### 12.2 Editor bottom bar and word count
- A bar under the editor: Bold, Italic, Underline, Insert Table (the section 11 popover), Bullet List, Numbered List, Math (Σ), all SF Symbols with tooltips; Format menu items Bold ⌘B, Italic ⌘I, Underline ⌘U.
- Pure core transforms (unit-tested), executed as one undoable edit through the funnel: bold `*…*`, italic `_…_`, underline `#underline[…]` wrap the selection or insert an empty pair with the caret inside, and unwrap when the selection or caret is already inside that markup (syntax mirror); lists toggle `- ` / `+ ` prefixes on every selected line (and convert between them); math wraps the selection in `$…$`, or on an empty line inserts `$ | $`.
- Right side: word count of the compiled document ("4 075 words", locale-formatted), from `tb_snapshot_word_count` (Unicode word segmentation over the text of all pages, computed on the engine thread with each compile); with a non-empty selection "12 of 4 075 words", the selection count coming from the prose ranges of the selected source text.

### 12.3 Preview toolbar
- Zoom out, zoom percentage (relative to the page's natural size; clicking it offers 50/75/100/125/150/200 % and Fit Width), zoom in, Fit Width; "Page X of Y" for the page most visible (clicking lets you jump to a page); Pop Out (the preview moves to its own window sharing the same `PreviewModel`; closing that window brings it back); Lock; Follow Cursor toggle (the section 7 setting, accent-tinted when on); Share (NSSharingServicePicker with the exported PDF) plus File > Export PDF….
- **Lock semantics:** locked (default) = the preview stays on the pinned document (initially the project's main file); unlocked = selecting a `.typ` file in the sidebar makes it the previewed document (engine `.setMain`). Persisted per project in `RecentProjects`.

### 12.4 Sidebar tabs
A SwiftUI `TabView` in the sidebar column (an inline bar of text tabs with the system glass selection, `.badge` for the error count): Files, Search, Outline, Issues, Changes. The column is at least 320 pt wide so the five titles fit. Symbols and References are not tabs: they are buttons (x.squareroot, books.vertical) in the editor's bottom format bar, each opening a 320 x 460 pt popover with the same view.
- **Files:** all files and folders (hidden ones skipped) with type icons: folder blue, `.typ` a Typst "t" icon in teal (our own drawn glyph, not the official logo artwork), PDF red document, images photo, `.bib` brown book, `typst.toml` brown package box, data files (csv/json/yaml/toml/xml) tablecells or braces, fonts textformat, anything else a plain document. Text files (`.typ`, `.bib`, `.toml`, `.csv`, `.json`, `.yaml`, `.yml`, `.txt`, `.md`, `.xml`) open in the editor; PDFs and images show a Quick Look preview. Context menu: Open With Default App, Reveal in Finder, and for `.typ` "Preview This Document". File operations are specified in section 13.
- **Search:** project-wide find (case-sensitive / whole word / regex options) over all text files, using in-memory buffer text for open files; results grouped by file with the line and the match highlighted; click opens the file and selects the match. Runs off the main thread, cancelled by a newer query.
- **Outline:** headings of the previewed document from the last successful compile (`tb_snapshot_outline`: level, numbering, title text, page, y, source file and UTF-16 offset), as a collapsible tree; click jumps the editor and the preview.
- **Symbols (format bar popover):** search field plus a grid of all symbols of typst's `sym` and `emoji` modules with their variants (`tb_symbols`, a static list of name and character), recently used first; click inserts by mode at the caret: math `alpha`, markup `#sym.alpha`, code `sym.alpha` (emoji likewise with `emoji.`). Handwriting recognition is out of scope for now.
- **Issues:** the diagnostics list moves here from the inspector (the inspector is removed); same content and click behaviour.
- **References (format bar popover):** entries of every `.bib` (and hayagriva `.yml`) file in the project, parsed with the `hayagriva` crate already in typst's dependency tree (`tb_bibliography(path or text)`): key, title, authors, year, type; search; click inserts `@key` in markup or `cite(<key>)` in code; a malformed file shows its parse error instead of entries.

### 12.5 Local packages
A Settings window (SwiftUI `Settings` scene) with "Local packages folder": the user picks it once (suggested `~/Library/Application Support/typst/packages`, the typst default data dir), stored as a security-scoped bookmark. The runtime passes it as the packages data dir (`SystemPackages::from_parts(Some(FsPackages::new(dir)), cache, universe)`), so `@local/...` (and any other namespace folder there) resolve, and package completion lists them with descriptions from their `typst.toml`.

Implementation (see RATIONALE "Unit: local packages"): `tb_runtime_set_packages_dir(rt, dir)` (empty clears) swaps an `Arc<PathBuf>` behind a lock in the runtime; each world reads it at the start of every compile and completion. `LocalPackagesFolder` (core, `Access.swift`) owns the bookmark and the scoped access and calls `TypstRuntime.setPackagesDir`, which also tells every open `Project` to recompile (`EngineMessage.recompile`).

## 13. File management in the sidebar

User request (2026-11-17): "Dateien verwalten". Section 12.4 deliberately postponed it because a `RelPath` is the identity of an open `Buffer`, its engine overlay, the main/pinned document in `RecentProjects`, `selectedFile`, `EditLog` entries, diagnostics, in-flight requests and pending autosaves. This section defines the protocol first.

### Operations (core, `Project`, all `@MainActor`, all throwing with a user-presentable error)
- `createFile(named:in:) -> RelPath` and `createFolder(named:in:) -> RelPath`: fail if the name exists or is invalid (empty, contains `/` or `:`, starts with `.` so it would be hidden, or is `.`/`..`). A new text file opens in the editor and becomes `selectedFile`.
- `rename(_ path: RelPath, to newName: String)` and `move(_ path: RelPath, into folder: RelPath)`: one shared implementation `relocate(from:to:)` for files and folders (a folder relocates every descendant).
- `duplicate(_ path: RelPath) -> RelPath`: "name copy.ext", "name copy 2.ext", …
- `moveToTrash(_ path: RelPath)`.
- `importItems(_ urls: [URL], into folder: RelPath)`: copies files dropped from Finder into the project (never moves the user's originals); name clashes get the "copy" suffix.
- `refreshFiles()`: rescans the tree; also called by a macOS FSEvents watcher on the project root and on app activation, so files added in Finder appear. The watcher subscribes to file-level events and reacts only to structural ones (created, removed, renamed), not content writes (autosave would otherwise rescan every 1.5 s); events are coalesced (~0.3 s); the echo of the app's own operations is skipped; the tree is not rebuilt while an inline rename is being edited; selection and expanded folders survive a refresh (keyed by `RelPath`).

### Relocate protocol (the identity change), in this order, aborting before any disk change if a step fails
0. **Quiesce writes:** pause autosave for every buffer at or under the old path from here on (resumed after step 4), and wait until their per-file writer queues are EMPTY (not merely queued), so no write can land on the old path after the move.
1. **Save** every dirty buffer at or under the old path (`saveAll` for those buffers). A failed save aborts the operation with that error; nothing has moved.
- Steps 2–4 run with NO suspension point between `moveItem` and the end of the re-key (no `await` in between), so no autosave or other main-actor work can observe a half-moved state.
- **Case-only renames** (`main.typ` → `Main.typ`) on case-insensitive APFS go through a temporary name; the "name exists" check ignores the item itself. `RelPath` equality stays case-sensitive.
2. **Disk:** `FileManager.moveItem(at:to:)` inside the project root (same volume, atomic). Failure aborts; buffers and overlays are untouched.
3. **Engine:** one inbox message `.relocate([(old, new)])`, ordered like any edit: the Rust world re-creates each overlay under the new `FileId` with the same text (`tb_world_relocate_overlay(old, new)`, a fresh `Source` is fine), drops the old overlay, re-points the world's MAIN `FileId` when the main file is at or under the moved path, and resets the file store so disk reads see the new layout.
4. **Re-key in Swift, same objects:** each affected `Buffer` keeps its `NSTextStorage`, `UndoManager`, selection and syntax mirror; only its `path` changes (and its highlighter kind if the extension changed, e.g. `.txt` → `.typ`). The buffers dictionary, `selectedFile`, the main/pinned document (and `RecentProjects`), per-file selection memory and `EditLog` entries are rewritten old → new. Diagnostics and the outline are re-derived from the next compile, which the relocate triggers.
5. **In flight:** completion, hover and jump replies for an old path are dropped (they resume `nil` per the exactly-once rules or fail the path check); pending autosave tasks look buffers up by object, not by path.
- After a relocate, search results are re-run (or cleared) and diagnostics whose files no longer exist are dropped until the next compile, so clicking an issue never opens a missing file.
- References in other files (`#include "kapitel.typ"`) are offered for update after an in-app rename or move; see design/14d-files-safety.md.
- File operations have undo, a file deleted outside the app while open shows the missing-file banner, and an open file renamed in Finder is followed; see design/14d-files-safety.md.

### Trash protocol
1. Save dirty buffers at or under the path (so the trashed copy has the latest text; a failed save aborts).
2. Engine `.drop([paths])` removes their overlays; buffers are closed (removed, undo history discarded).
3. `FileManager.trashItem(at:resultingItemURL:)`; failure (e.g. no trash on that volume) aborts with the error and re-opens nothing because the buffers were saved.
4. If the main/pinned document was trashed, the previewed document becomes the selected `.typ` if any, else the first `.typ` in the root, else none (the preview shows "No document").
- Tests inject the trash function so they never touch the user's Trash.

### App
- Files tab: context menu New File…, New Folder…, Rename, Duplicate, Move to Trash (⌘⌫), plus the existing Reveal in Finder / Open With Default App / Preview This Document; a "+" menu button (New File, New Folder) in the tab's footer. Inline renaming in the list like Finder/Xcode (Return or double-click-pause on the selected row starts editing; Return commits, Esc cancels; the name part before the extension is preselected). New items appear as an editable row named "Untitled.typ" / "untitled folder" in the selected folder.
- Drag and drop: rows can be dragged onto folders (and the root) to move them (a folder can never be dropped into itself or a descendant); Finder files dropped onto the list are imported (copied).
- The same actions in the File menu (New File… ⌥⌘N, New Folder… ⇧⌘N, Rename, Duplicate, Move to Trash) acting on the sidebar selection, so they are also reachable without the context menu. **⌘⌫ (Move to Trash) is enabled only while the file list has keyboard focus**, as in Finder and Xcode; in the editor ⌘⌫ keeps its text meaning (delete to line start) and must never trash a file.
- Moving to the Trash asks for confirmation only when the item is a folder with more than one file; single files go straight to the Trash (recoverable via Finder's Put Back, as in Finder).

## 14. Welcome window, new projects and Universe templates

### Welcome window
- Its own `Window("Welcome to Typo", id: "welcome")`, the first scene, so SwiftUI shows it at launch when no project window is restored and on a Dock click with no windows; ⇧⌘1 and the Window menu reopen it. Hidden title bar, no traffic lights (the view draws a round glass close button, Esc closes), 440 × 560 pt, not resizable, not restored.
- Layout as in Xcode 27: app icon, name, version (`CFBundleShortVersionString` = `MARKETING_VERSION`), three capsule buttons **Open…** (files and folders), **New Project…**, **Templates…**, then the recent projects in a rounded panel (Typst document icon, name, path with `~`). The first row is selected; Return or a double-click opens, as does each button's success, which closes the welcome window.
- Opened files (Finder, `open`) are external events of the welcome scene (`handlesExternalEvents(matching: ["*"])`); the project `WindowGroup` takes none, and its nil-valued window (only restored from older builds) redirects to the welcome window. File ▸ New Window no longer exists: ⌘N is **New Project…**, followed by **New Project from Template…**.

### New project
- NSSavePanel ("Create", name "Untitled") → a new folder with `main.typ` holding `#set page(paper: …)` (us-letter in US/CA/MX, else a4) and `#set text(lang: …)` from the locale → registered in Recent Projects and opened. The folder must not exist: the panel's "Replace" ends in an error alert, and nothing is merged or deleted.

### Templates (`typst init`)
- Source: the @preview index the app already caches (DESIGN 10). `tb_runtime_set_package_index` also keeps every entry with a `template` object and a compatible `compiler` (the same `IndexPackage::compatible()` rule as the package list), one per name at its highest compatible version, sorted by name; `tb_runtime_templates` returns them as JSON (`name, version, description, authors, categories, path, entrypoint`). `TypstRuntime.templates()` decodes it, awaiting one index revalidation when nothing is cached yet.
- Thumbnails: `https://packages.typst.org/preview/thumbnails/<name>-<version>-small.webp` via `AsyncImage`.
- `tb_runtime_fetch_package(spec, &ok)` resolves a package with the world loader's order (local packages dir, cache, Universe download into the cache) and returns its directory or an error. `TypstRuntime.createProject(from:at:)` runs it off the main actor, checks that the template directory and entrypoint exist inside the package, creates the (non-existent) destination and copies the template directory's contents into it, and returns the entrypoint as the main file. The template's own `@preview` import then hits the cache on the first compile.
- Chooser: `Window("New Project from Template", id: "templates")`, 900 × 620, `NavigationSplitView` with All Templates and the categories present (paper, thesis, report, book, cv, presentation, poster, flyer, office, fun first, the rest alphabetical), toolbar search over name, description and authors, a grid of page previews with name and description, a footer with the selection's name, version and authors, Cancel and **Create…** (double-click a card does the same). Create asks for the folder with the same Save panel, shows "Downloading <name>…", then opens the project and closes the chooser and the welcome window. Errors are alerts.
- Tests: the catalog from the real index fixture (912 templates; `charged-ieee` 0.1.4 with its thumbnail URL), copying a local-packages fixture template (only the template directory, entrypoint returned), an existing destination left untouched, an unresolvable spec failing without creating a folder.

## 15. Thesis features (built in parallel lanes; each has its own section file)

| Feature | Section | Entry points |
|---|---|---|
| Export PDF, PDF/A-2b, PNG, SVG; word goal, today's words, words per chapter | `design/14b-export-progress.md` | File ▸ Export; the bottom-bar word count |
| References by DOI/ISBN, citation picker, richer `@` completion | `design/14c-citations.md` | References tab "Add Reference…"; Format ▸ Insert Citation… ⇧⌘C |
| Path references updated on rename/move, missing-file banner, undo for file operations, snapshots | `design/14d-files-safety.md` | sidebar; File ▸ Snapshots… |
| Images by drop and paste, editor font size, themes, Focus Mode, split editor, heading folding | `design/14e-images-comfort.md` | View menu; Settings |
| Jump to label definition, rename labels, TODO list | `design/14f-labels-todos.md` | Navigate menu, ⌘-click; Issues tab |

Shared foundations every lane used (Packages/Typo): `Project.edit(path, [Replacement], actionName:)` / `Buffer.apply` edit any project text file, open or not, through the storage funnel as one undo step; `TypstSyntax.tokens(in:)` scans any Typst source for labels, refs, strings and comments.

Menu placement rule: items placed with `CommandGroup(after: .saveItem)` never appear in this app (no document scene), so File-menu items go `after: .newItem`.
