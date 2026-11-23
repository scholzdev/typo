# Design task: app skeleton for a native Typst editor

## Artifact
A design package (README-style usage, module map, type sketch with signatures and `fatalError("not implemented")` bodies, rationale per the architect rationale template) for the first real build of the app. Not code that runs. Swift 6.4 with strict concurrency, plus the C ABI of the Rust bridge.

## Product
A native Typst editor. "Richtig schön macOS native." macOS app first; iPad app later on the same core. Deployment targets: **macOS 27+ and iOS/iPadOS 27+** (Xcode 27.2, Swift 6.4.2). Distribution (App Store or direct) is undecided, so the design must work inside the App Sandbox.

Skeleton scope (MVP), all of it must be covered by the design:
- Open a project: a folder (Typst root) with a main file. Opening a single `.typ` also works (root = its folder). Open Recent and window restoration across launches. Sandbox: security-scoped bookmarks; on iOS the Files folder picker.
- File sidebar for the project folder; the user can open and edit any `.typ` file in it, not only the main file. Unsaved edits in a non-main file must reach the compiler.
- Editor: TextKit 2 text view (NSTextView now, UITextView later) with line numbers, system spell check, undo. Syntax highlighting can be a stub with a clear seam.
- Live preview while typing, no save needed. Pages rendered as images (decided by the spike, see below). Only visible pages are rendered; only pages whose content changed are re-rendered.
- Diagnostics: list plus inline marks in the editor, click jumps to the location (file + UTF-16 range).
- PDF export on demand.
- `@preview/...` packages download automatically into an app-chosen cache dir. System fonts usable.
- Saving: autosave of edited files to disk; Cmd-S works.

Out of scope now (design must not block them): autocomplete/hover (typst-ide), preview-to-source and source-to-preview jump, themes, templates, tabs, vim mode, iCloud, iPad UI, external-change detection.

## Hard facts from the spike (spike/RESULTS.md, spike/NOTES-typst-0.15-api.md)
- typst 0.15.1 embedded as a Rust staticlib behind a C ABI in an XCFramework works on macOS and iOS. The spike's ABI (spike/include/typst_bridge.h, spike/typst-bridge/src/lib.rs) is a starting point, not a contract; redesign it freely.
- The Rust `World` is single-threaded in practice: one compile at a time per world. It holds the main file's `Source` in memory and edits it in place with `Source::edit` (that is what makes compiles incremental). Other files are served from disk via typst-kit FileStore. Edits arrive as UTF-16 ranges (what NSTextStorage/NSRange gives) and are converted with `Lines::utf16_to_byte`.
- Per keystroke on M2 Pro, release: compile 22 ms at 38 pages, 94 ms at 150 pages (grows linearly with length). Render one A4 page at 2 px/pt to premultiplied RGBA: ~2 ms warm, ~8 ms cold, 8 MB per page. Full PDF export 18 ms (38 p) / 71 ms (150 p). Cold first compile 0.3 to 1.1 s, plus package download time if not cached.
- Consequences: compile must never run on the main thread; keystrokes must never be dropped or reordered, but compiles must coalesce (latest wins) so a fast typist does not queue 10 compiles. Page images need a bounded cache.
- Verified in source: `Frame` derives `Clone, Hash` (typst-library layout/frame.rs:17) and `Page` derives `Clone, Hash` (typst-layout document.rs:82), so `typst::utils::hash128(&page)` can tell which pages changed between compiles. `PagedDocument` is `Clone` and Arc-backed (EcoVec), so keeping a snapshot is cheap.
- Verified: typst-cli renders pages with rayon `par_iter` (typst-cli compile.rs:498), so `Page` is `Sync`. Rendering pages of a finished snapshot on another thread while the next compile runs is possible.
- The incremental cache (comemo) is process-wide: `comemo::evict(max_age)` is a free function over a global cache (comemo memoize.rs:100) with no world parameter. With two project windows open, every window shares one cache, and evicting after each compile in one window ages out the other window's entries. Two worlds may compile concurrently on different threads. Eviction policy needs exactly one owner.
- A compile can block for seconds: the first compile with an uncached package took 2.3 s on the simulator because the package download runs inside compile. Edits keep arriving meanwhile, and the UI needs a visible "downloading / compiling" state.
- Staleness: a compile runs in the background while the user keeps typing. When its diagnostics (UTF-16 ranges) and page snapshot reach the main actor, the text may have changed since. Every result must say which revision of each file it was computed against, and the design must state what the main actor does with a result older than the current text (shift ranges across the newer edits, or drop it and wait for the next one).
- Diagnostics come back with file id, message, severity, hints, and a UTF-16 range relative to that file's text.
- Fonts: enumerating CoreText font URLs and reading every file to build FontInfo takes ~2 s on macOS (446 files) and 0.6 s on the iOS simulator. Embedded fonts (Libertinus, New Computer Modern, DejaVu Sans Mono) are available instantly. Needs a persistent font index cache or background loading.
- Packages: typst-kit `SystemPackages` with an explicit cache dir and `SystemDownloader` (native-tls) works on macOS and in the iOS simulator. The downloader is synchronous and runs inside compile.
- Size: ~42 MB stripped executable without LTO.

## Questions the design must answer
1. Module map: which Swift packages/targets, what lives in each, what the app target imports. The core must build for iOS 27 unchanged.
2. Rust C ABI: handles, ownership, memory freeing, how in-memory buffers for several files are passed, how per-page change info (hash, size) comes back, how page rendering is requested, error/diagnostic transport. Keep it minimal.
3. Swift engine API used by the app: the few calls the UI makes. Which concurrency construct owns the world (actor with a custom serial executor on a dedicated thread? a serial queue?), how edits stay ordered while compiles coalesce, how results reach the main actor.
4. Text ownership: who is the source of truth for a file's text (NSTextStorage? a model string? the engine's copy? disk?). How edits flow from the text view to the engine and to disk, without split ownership.
5. Project/window model: SwiftUI scene structure for "one window per project folder", how security-scoped access is held and restored, Open Recent.
6. Preview pipeline: page layout model, image cache keyed by what, how visible pages are tracked, how a changed page hash triggers a re-render, memory bound.
7. Diagnostics: domain type, how they map to inline marks and the list, how jumping opens the right file and selects the range, and how stale results are handled.
9. Who owns comemo eviction when several projects are open.
8. Font index caching and package cache location.
