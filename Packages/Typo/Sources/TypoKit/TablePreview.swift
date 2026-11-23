import CoreGraphics
import Foundation
import TypstEngine

/// Compiles the project with one file's text swapped in, on its own world (never the engine's), and renders table cells
/// as the document would set them, or the page area around the whole table. For an open table editor.
public final class TablePreviewer: @unchecked Sendable {      // `world` is touched only on `queue`
    private let queue = DispatchQueue(label: "typstcore.table-preview", qos: .userInitiated)
    private let world: WorldHandle
    private let root: URL, main: RelPath
    public static let maxCells = 400

    init?(runtime: TypstRuntime, root: URL, main: RelPath, fonts: [String]) {
        guard let w = WorldHandle(runtime: runtime, root: root, main: main, onDownload: { _ in }) else { return nil }
        w.setProjectFonts(fonts)
        world = w
        self.root = root
        self.main = main
    }

    /// Each distinct non-empty cell markup in `cells` (the first `maxCells`) rendered on a page of its own, appended to the
    /// main file, so the document's set rules, labels and numbering apply. `file` reads `text` (the table as edited);
    /// `overlays` stand in for other files (unsaved buffers). `fill` is a Typst colour, `size` the text size in points.
    /// A cell missing from the result could not be rendered (empty, or the compile failed).
    public func renderCells(_ cells: [String], file: RelPath, text: String, overlays: [RelPath: String] = [:],
                            fill: String, size: Double, pixelsPerPoint: Float = 2) async -> [String: CGImage] {
        var seen = Set<String>()
        let unique = Array(cells.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && seen.insert($0).inserted }.prefix(Self.maxCells))
        guard !unique.isEmpty else { return [:] }
        func page(_ body: String) -> String {
            "#page(width: auto, height: auto, margin: 0pt, fill: none, header: none, footer: none, background: none, foreground: none, numbering: none, columns: 1)[#set text(fill: \(fill), size: \(size)pt, top-edge: \"ascender\", bottom-edge: \"descender\");\(body)]"
        }
        let main = main
        let mainText = file == main ? text : overlays[main] ?? (try? String(contentsOf: root.appending(path: main.raw), encoding: .utf8))
        guard let mainText else { return [:] }
        // A template's `#show:` can put pages after ours (a bibliography), so a sentinel page says where the cells start.
        let sentinel = mainText + "\n\n" + page("x")
        let x = (sentinel as NSString).length - 1     // just after the sentinel's "x", before its "]"
        let full = sentinel + "\n" + unique.map(page).joined(separator: "\n")
        let found: (Snapshot, Int)? = await withCheckedContinuation { c in
            queue.async { [world] in
                for (p, t) in overlays where p != file && p != main { world.setText(p, t) }
                if file != main { world.setText(file, text) }
                world.setText(main, full)
                let snapshot = world.compile()
                let at = world.jumpFromCursor(main, cursor: x).first?.page
                c.resume(returning: at.map { (snapshot, $0 + 1) })
            }
        }
        guard let (snapshot, first) = found, first + unique.count <= snapshot.pageCount else { return [:] }
        var out: [String: CGImage] = [:]
        for (i, cell) in unique.enumerated() {
            out[cell] = await snapshot.render(page: first + i, pixelsPerPoint: pixelsPerPoint)
        }
        return out
    }

    /// The part of the page that shows `range` of `file` (UTF-16) when `file` reads `text`. `overlays` stand in for other
    /// files (unsaved buffers). Nil when nothing in the range lands on a page (no text in it, or the compile failed).
    public func render(file: RelPath, text: String, range: NSRange, overlays: [RelPath: String] = [:], pixelsPerPoint: Float = 2) async -> CGImage? {
        let found: (Snapshot, Int, ClosedRange<CGFloat>, ClosedRange<CGFloat>)? = await withCheckedContinuation { c in
            queue.async { [world] in
                for (p, t) in overlays where p != file { world.setText(p, t) }
                world.setText(file, text)
                let snapshot = world.compile()
                guard snapshot.pageCount > 0 else { return c.resume(returning: nil) }
                // Positions exist only for text, so ask at the starts of the first and last few cells' contents.
                let candidates = Self.textOffsets(in: text, range: range)
                var hits: [PreviewPosition] = []
                for at in candidates.prefix(6) + candidates.suffix(6) { hits += world.jumpFromCursor(file, cursor: at) }
                guard let page = hits.first?.page else { return c.resume(returning: nil) }
                let points = hits.filter { $0.page == page }.map(\.point)
                let ys = points.map(\.y), xs = points.map(\.x)
                c.resume(returning: (snapshot, page, ys.min()!...ys.max()!, xs.min()!...xs.max()!))
            }
        }
        guard let (snapshot, page, ys, xs) = found, let image = await snapshot.render(page: page, pixelsPerPoint: pixelsPerPoint) else { return nil }
        let scale = CGFloat(image.height) / snapshot.pages[page].size.height
        let seed = CGRect(x: xs.lowerBound * scale, y: ys.lowerBound * scale,
                          width: (xs.upperBound - xs.lowerBound) * scale + 1, height: (ys.upperBound - ys.lowerBound) * scale + 1)
        guard let ink = Self.inkBounds(image, seed: seed, scale: scale) else { return image }
        return image.cropping(to: ink.insetBy(dx: -10 * scale, dy: -8 * scale).intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))) ?? image
    }

    /// The table's drawn area: grows from `seed` (cell text, in pixels) through every row and column with ink, stopping
    /// at a blank band. A caption sits closer than the gap to the next block, so it stays; the text around goes.
    static func inkBounds(_ image: CGImage, seed: CGRect, scale: CGFloat) -> CGRect? {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let px = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))   // row 0 of the buffer is the image's top row
        func inkRow(_ y: Int, _ x0: Int, _ x1: Int) -> Bool { (x0..<x1).contains { px[y * w + $0] < 200 } }
        func inkCol(_ x: Int, _ y0: Int, _ y1: Int) -> Bool { (y0..<y1).contains { px[$0 * w + x] < 200 } }
        let gapUp = Int(9 * scale), gapDown = Int(10 * scale), gapSide = Int(12 * scale)
        var top = max(0, Int(seed.minY)), bottom = min(h, Int(seed.maxY) + Int(14 * scale))
        var left = max(0, Int(seed.minX)), right = min(w, Int(seed.maxX) + 1)
        for _ in 0..<3 {   // widening can reveal taller rows and the other way round
            var x = left - 1, blank = 0
            while x >= 0 && blank <= gapSide { if inkCol(x, top, bottom) { left = x; blank = 0 } else { blank += 1 }; x -= 1 }
            x = right; blank = 0
            while x < w && blank <= gapSide { if inkCol(x, top, bottom) { right = x + 1; blank = 0 } else { blank += 1 }; x += 1 }
            var y = top - 1; blank = 0
            while y >= 0 && blank <= gapUp { if inkRow(y, left, right) { top = y; blank = 0 } else { blank += 1 }; y -= 1 }
            y = bottom; blank = 0
            while y < h && blank <= gapDown { if inkRow(y, left, right) { bottom = y + 1; blank = 0 } else { blank += 1 }; y += 1 }
        }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// Offsets just inside `[` where a letter or digit follows: text the layout can place.
    static func textOffsets(in text: String, range: NSRange) -> [Int] {
        let ns = text as NSString
        var out: [Int] = []
        var i = range.location
        while i + 1 < min(NSMaxRange(range), ns.length) {
            // Bold or emphasised header cells start with `*` or `_`; jump past it to the text.
            var j = i + 1
            while j < min(NSMaxRange(range), ns.length), [0x2A, 0x5F].contains(ns.character(at: j)) { j += 1 }
            if ns.character(at: i) == 0x5B, j < ns.length, let s = UnicodeScalar(ns.character(at: j)), CharacterSet.alphanumerics.contains(s) { out.append(j + 1) }
            i += 1
        }
        return out
    }
}

extension Project {
    /// A previewer for this project; one per open table editor (it holds a world of its own).
    public func tablePreviewer() -> TablePreviewer? { TablePreviewer(runtime: runtime, root: root, main: main, fonts: projectFontPaths) }

    /// The text of every open file, for the `overlays:` of `TablePreviewer`.
    public var openTexts: [RelPath: String] { buffers.mapValues { $0.storage.string } }
}
