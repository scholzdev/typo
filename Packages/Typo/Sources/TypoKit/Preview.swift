import CoreGraphics
import Foundation
import Observation
import TypstEngine

public struct ImageKey: Hashable, Sendable {
    public let hash: UInt128
    public let pixelsPerPoint: Float      // displayScale * zoom, rounded to 1/8
    public init(_ hash: UInt128, pixelsPerPoint: CGFloat) {
        self.hash = hash
        self.pixelsPerPoint = Float((pixelsPerPoint * 8).rounded() / 8)
    }
}

/// Counting semaphore for async code.
actor RenderSlots {
    private var free: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(limit: Int) { free = limit }
    func acquire() async {
        if free > 0 { free -= 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        if waiters.isEmpty { free += 1 } else { waiters.removeFirst().resume() }
    }
}

/// How the preview sizes its pages. `nil` on `PreviewModel.fit` means a zoom the user picked by hand.
public enum PreviewFit: String, CaseIterable, Sendable {
    case width, page, twoPages

    public var title: String {
        switch self {
        case .width: "Fit Width"
        case .page: "Fit Page"
        case .twoPages: "Two Pages"
        }
    }
}

/// Shows the latest successful document. A failed compile changes diagnostics, not pages.
@MainActor @Observable public final class PreviewModel {
    public private(set) var pages: [PageInfo] = []
    /// True while a failed compile left the last good render on screen.
    public private(set) var isStale = false
    /// Page width = `fitWidth * zoom`; a fit mode recomputes it whenever the viewport or the page size changes.
    public var zoom: CGFloat = 1
    public var fit: PreviewFit? = .width { didSet { refit() } }
    /// Pages per row: 2 in the two-page mode, kept when the user then zooms by hand.
    public private(set) var columns = 1
    /// The size of the scroll view, set by the preview view; Fit Page needs its height.
    public var viewport: CGSize = .zero { didSet { if viewport != oldValue { refit() } } }
    public var showsThumbnails: Bool = UserDefaults.standard.bool(forKey: "previewShowsThumbnails") {
        didSet { UserDefaults.standard.set(showsThumbnails, forKey: "previewShowsThumbnails") }
    }
    /// Tints the pages dark on screen only; export and print stay as written.
    public var darkPages: Bool = UserDefaults.standard.bool(forKey: "previewDarkPages") {
        didSet { UserDefaults.standard.set(darkPages, forKey: "previewDarkPages") }
    }
    /// Where the editor's caret (or a click on the outline) lands in the preview, and what to do about it.
    /// `targetSerial` changes on every aim, so an equal target still triggers the view.
    public private(set) var target: PreviewPosition?
    public private(set) var targetDecision = SyncDecision(request: false, scrollIfOutside: false, marker: false)
    public private(set) var targetSerial = 0
    public private(set) var targetDate = Date.distantPast      // lets a lazily created page view tell a fresh aim from an old one
    /// Set by the view when the user scrolls by hand; cleared when a navigation sync aims.
    public var userScrolled = false
    /// Set by whichever preview view is on screen: the column width zoom 1 fits, and the page most in view.
    public var fitWidth: CGFloat = 0 { didSet { if fitWidth != oldValue { refit() } } }
    public var visiblePage = 0
    /// A request to scroll a page to the top; `serial` changes on every request.
    public private(set) var pageRequest = (page: 0, serial: 0)
    public func jump(toPage page: Int) { pageRequest = (page, pageRequest.serial + 1) }
    /// A zoom by hand leaves the fit mode.
    public func zoom(by factor: CGFloat) {
        set(zoom: zoom * factor)
    }
    public func set(zoom z: CGFloat) {
        fit = nil
        zoom = min(max(z, PreviewMath.zoomRange.lowerBound), PreviewMath.zoomRange.upperBound)
    }

    private func refit() {
        guard let fit else { return }
        columns = fit == .twoPages ? 2 : 1
        guard let size = pages.first?.size else { return }
        zoom = PreviewMath.zoom(fitting: fit, page: size, viewport: viewport, fitWidth: fitWidth)
    }
    /// True while the preview lives in its own window; the main window then hides its column.
    public var isPoppedOut = false
    public var followsCursor: Bool = UserDefaults.standard.object(forKey: "previewFollowsCursor") as? Bool ?? true {
        didSet { UserDefaults.standard.set(followsCursor, forKey: "previewFollowsCursor") }
    }
#if os(iOS)
    private var cache = ImageLRU(byteLimit: 128 << 20)
#else
    private var cache = ImageLRU(byteLimit: 256 << 20)
#endif
    /// One unit of work per key. Callers only count themselves in and out; the work is never cancelled,
    /// it skips itself when nobody waits at the moment it gets its slot.
    @MainActor final class Work {
        var waiters = 0
        var task: Task<Void, Never>!
        let page: PageInfo, key: ImageKey      // read through the object: a UInt128 captured by the Task closure arrived garbled (debug build)
        init(_ page: PageInfo, _ key: ImageKey) { self.page = page; self.key = key }
    }
    var inFlight: [ImageKey: Work] = [:]
    private(set) var renderCount = 0                          // test hook
    private var shown: [Int: ImageKey] = [:]                  // per page index: the newest image that landed
    let renderSlots = RenderSlots(limit: 2)           // flinging through 150 pages stays bounded

    /// Also drops every cached key whose hash is not in the new page set. Without this, a reflowing
    /// page inserts ~8 MB per keystroke and LRU pressure evicts unchanged visible pages, whose
    /// task(id:) never fires again. An undo that brings a hash back costs one ~8 ms render.
    /// No document at all (the main file is gone): the pages and their images go, unlike a failed compile.
    func clear() {
        pages = []
        isStale = false
        shown = [:]
        cache.retain(hashes: [], keeping: [])
    }

    func show(_ s: Snapshot) {
        let p = s.pages
        guard !p.isEmpty else { isStale = !pages.isEmpty; return }
        let oldSize = pages.first?.size
        pages = p
        isStale = false
        if p[0].size != oldSize { refit() }
        shown = shown.filter { $0.key < p.count }
        // A changed page keeps its previous image until its replacement lands, so the preview never flashes white.
        cache.retain(hashes: Set(p.map(\.hash)), keeping: Set(shown.values))
    }

    func aim(_ p: PreviewPosition, _ d: SyncDecision) {
        target = p
        targetDecision = d
        targetDate = .now
        targetSerial += 1
        if d.marker { userScrolled = false }              // a navigation lifts the "user scrolled" hold
    }

    /// The image for `key`, else the last one shown for page `index` (stale but visible until the render lands).
    public func image(for key: ImageKey, index: Int? = nil) -> CGImage? {
        cache[key] ?? index.flatMap { shown[$0] }.flatMap { cache[$0] }
    }

    private func landed(_ key: ImageKey, at index: Int) {
        let old = shown[index]
        shown[index] = key
        if let old, old != key, !pages.contains(where: { $0.hash == old.hash }) { cache.remove(old) }
    }

    /// Called from PageView.task(id:). A cache hit returns at once, so pages whose hash survived the
    /// edit never re-render. A thumbnail does not become the page's stale fallback, which would show blurry.
    public func render(_ page: PageInfo, _ key: ImageKey, thumbnail: Bool = false) async {
        if cache[key] == nil {
            let work = inFlight[key] ?? start(page, key)
            work.waiters += 1
            await withTaskCancellationHandler {
                await work.task.value
            } onCancel: {
                Task { @MainActor in work.waiters -= 1 }
            }
        }
        if cache[key] != nil { cache.touch(key); if !thumbnail { landed(key, at: page.id) } }
    }

    private func start(_ page: PageInfo, _ key: ImageKey) -> Work {
        let work = Work(page, key)
        inFlight[key] = work
        work.task = Task {
            await renderSlots.acquire()
            defer { Task { await renderSlots.release() } }
            // No waiter left: the view scrolled away while we queued. Removal and check share one actor turn,
            // so a late joiner either finds this work and counts in first, or starts a new one.
            if work.waiters > 0 {
                renderCount += 1
                if let img = await work.page.snapshot.render(page: work.page.id, pixelsPerPoint: work.key.pixelsPerPoint) {
                    cache.insert(img, for: work.key)
                }
            }
            if inFlight[work.key] === work { inFlight[work.key] = nil }
        }
        return work
    }
}

/// Byte-bounded LRU. Cost = width*height*4. Main actor only, so no lock. Recency is refreshed by
/// `touch` (called from `render` on a hit, i.e. each time a page view appears), never by the
/// subscript, which SwiftUI calls during body evaluation. Eviction then hits scrolled-away pages.
struct ImageLRU {
    private struct Entry { let image: CGImage; var tick: UInt64 }
    private var entries: [ImageKey: Entry] = [:]
    private var bytes = 0
    private var clock: UInt64 = 0
    private let byteLimit: Int

    init(byteLimit: Int) { self.byteLimit = byteLimit }

    private static func cost(_ i: CGImage) -> Int { i.width * i.height * 4 }

    subscript(key: ImageKey) -> CGImage? { entries[key]?.image }

    mutating func touch(_ key: ImageKey) {
        clock += 1
        entries[key]?.tick = clock
    }

    mutating func remove(_ key: ImageKey) {
        if let e = entries.removeValue(forKey: key) { bytes -= Self.cost(e.image) }
    }

    mutating func retain(hashes: Set<UInt128>, keeping: Set<ImageKey> = []) {
        for (k, e) in entries where !hashes.contains(k.hash) && !keeping.contains(k) {
            bytes -= Self.cost(e.image)
            entries[k] = nil
        }
    }

    mutating func insert(_ image: CGImage, for key: ImageKey) {
        if let old = entries[key] { bytes -= Self.cost(old.image) }
        clock += 1
        entries[key] = Entry(image: image, tick: clock)
        bytes += Self.cost(image)
        while bytes > byteLimit, entries.count > 1, let oldest = entries.min(by: { $0.value.tick < $1.value.tick }) {
            bytes -= Self.cost(oldest.value.image)
            entries[oldest.key] = nil
        }
    }

    mutating func removeAll() { entries = [:]; bytes = 0 }         // memory warning
}
