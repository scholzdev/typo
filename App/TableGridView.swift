import AppKit
import SwiftUI
import TypoKit
import TypstEngine

/// The spreadsheet grid of the table editor, in a scroll view.
struct TableGrid: NSViewRepresentable {
    let state: TableSheetState
    let completions: CellCompletion
    /// Engine-backed completion for the cell being edited.
    let complete: (_ row: Int, _ column: Int, _ text: String, _ caret: Int, _ request: CellCompletion.Request) async -> [CompletionItem]
    let cancel: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        scroll.borderType = .noBorder
        let grid = TableGridView(state: state)
        scroll.documentView = grid
        scroll.contentView.postsBoundsChangedNotifications = true
        scroll.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(grid, selector: #selector(TableGridView.scrolled), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        NotificationCenter.default.addObserver(grid, selector: #selector(TableGridView.scrolled), name: NSView.frameDidChangeNotification, object: scroll.contentView)
        DispatchQueue.main.async { grid.window?.makeFirstResponder(grid) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let grid = scroll.documentView as? TableGridView else { return }
        grid.completions = completions
        grid.complete = complete
        grid.onCancel = cancel
        // Reading these here makes SwiftUI call back on every change of the model, the selection or the rendered cells.
        _ = (state.model, state.cursor, state.anchor, state.cellImages, state.showsRaw)
        grid.refresh()
    }
}

/// Draws the cells, the column bar (A, B, C …) and the row gutter; the bar, the header row and the gutter stay put while scrolling.
/// Owns the keyboard and mouse of a spreadsheet; one text field edits the active cell.
final class TableGridView: NSView, NSTextFieldDelegate, NSMenuItemValidation {
    let state: TableSheetState
    var completions = CellCompletion()
    var complete: ((Int, Int, String, Int, CellCompletion.Request) async -> [CompletionItem])?
    var onCancel: () -> Void = {}

    static let gutter: CGFloat = 40, bar: CGFloat = 24, rowHeight: CGFloat = 26, maxRowHeight: CGFloat = 160, minColumn: CGFloat = 36
    private(set) var widths: [CGFloat] = []
    private var lefts: [CGFloat] = []
    private var ys: [CGFloat] = []
    private var fills: [String: NSColor] = [:]
    private var styled: [String: NSAttributedString] = [:]       // highlighting is a Rust parse: cached per text and weight

    private let editor = CellEditorField()
    private var editing: TableSheetState.Point?
    private let popup = CompletionPopup()
    private var request: CellCompletion.Request?
    private var accepting = false, generation = 0
    private var drop: (column: Bool, at: Int)?                    // where a dragged row or column would land
    private var cellElements: [TableSheetState.Point: GridCellElement] = [:]

    init(state: TableSheetState) {
        self.state = state
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        editor.delegate = self
        state.commitEdit = { [weak self] in self?.commitEdit() }
        popup.onPick = { [weak self] in self?.accept($0) }
        setAccessibilityElement(true)
        setAccessibilityRole(.table)
        setAccessibilityLabel("Table cells")
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var undoManager: UndoManager? { state.undo }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // The window is a sheet only once it has been presented.
        DispatchQueue.main.async { [weak self] in TableSheetWindow.adopt(self?.window) }
    }

    // MARK: layout

    private var model: TableModel { state.model }
    private var visible: NSRect { visibleRect }

    private var laidOut: TableModel?
    private var laidOutImages: [String: NSImage] = [:]
    private var columnsStale: Bool { model != laidOut || images != laidOutImages }
    /// What the cells draw: their rendered images, or none when the grid shows the markup.
    private var images: [String: NSImage] { state.showsRaw ? [:] : state.cellImages }

    func refresh() {
        if columnsStale { layoutCells() }
        fit()
        if let e = editing { placeEditor(e) }
        cellElements = cellElements.filter { $0.key.row < model.rowCount && $0.key.column < model.columns.count }
        needsDisplay = true
        NSAccessibility.post(element: self, notification: .selectedCellsChanged)
    }

    /// Column widths from `columns:` (auto columns fit their text) and row heights; measuring text is the slow part, so only after a change.
    private func layoutCells() {
        laidOut = model
        laidOutImages = images
        let fallback: CGFloat = 120
        widths = model.columns.indices.map { c in
            switch model.columns[c].width {
            case .points(let v): max(Self.minColumn, v * 1.25)
            case .fraction(let v): max(Self.minColumn, min(400, 110 * v))
            case .auto, .other: autoWidth(c, fallback: fallback)
            }
        }
        var x = Self.gutter
        lefts = widths.map { w in defer { x += w }; return x }
        // A row grows to its tallest rendered cell; a merged cell over several rows does not stretch them.
        ys = [0]
        for r in 0..<model.rowCount {
            let tallest = model.columns.indices.map { c in
                let cell = model.cell(row: r, column: c)
                return cell.covered || cell.rowspan > 1 ? 0 : images[cell.text]?.size.height ?? 0
            }.max() ?? 0
            ys.append(ys[r] + max(Self.rowHeight, min(Self.maxRowHeight, tallest + 8)))
        }
        window?.invalidateCursorRects(for: self)
    }

    /// At least as large as the scroll view, so the bar and the gutter reach its edges.
    private func fit() {
        let size = NSSize(width: (lefts.last ?? Self.gutter) + (widths.last ?? 0) + 1, height: Self.bar + y(model.rowCount) + 1)
        let minSize = enclosingScrollView?.contentSize ?? size
        let want = NSSize(width: max(size.width, minSize.width), height: max(size.height, minSize.height))
        if frame.size != want { setFrameSize(want) }
    }

    /// The grid draws a cell's rendered image when it has one, so that is what is measured.
    private func autoWidth(_ c: Int, fallback: CGFloat) -> CGFloat {
        var w: CGFloat = 60
        for r in 0..<min(model.rowCount, 200) {
            let cell = model.cell(row: r, column: c)
            guard !cell.covered, cell.colspan == 1 else { continue }
            let drawn = images[cell.text]?.size.width
                ?? (cell.text as NSString).size(withAttributes: [.font: font(header: r < model.headerRows)]).width
            w = max(w, drawn + 18)
        }
        return min(w, 280)
    }

    @objc func scrolled() {
        fit()
        needsDisplay = true
        if let e = editing { placeEditor(e) }
    }

    private func font(header: Bool) -> NSFont { .systemFont(ofSize: NSFont.systemFontSize, weight: header ? .semibold : .regular) }

    /// Top of display row `r` below the bar, unscrolled; `y(rowCount)` is the bottom.
    private func y(_ r: Int) -> CGFloat {
        if ys.count != model.rowCount + 1 { layoutCells() }
        return ys[r]
    }

    private var headerHeight: CGFloat { y(model.headerRows) }

    /// The row whose band holds `offset` (as `y`); `rowCount` below the last row.
    private func rowIndex(_ offset: CGFloat) -> Int {
        var lo = 0, hi = model.rowCount
        while lo < hi { let mid = (lo + hi) / 2; if y(mid + 1) > offset { hi = mid } else { lo = mid + 1 } }
        return lo
    }

    /// Top of display row `r`: the header row sticks under the bar while the body scrolls beneath it.
    private func top(_ r: Int) -> CGFloat {
        r < model.headerRows ? visible.minY + Self.bar + y(r) : Self.bar + y(r)
    }

    /// The rectangle of the (merged) cell whose top-left slot is (`r`, `c`).
    func rect(_ r: Int, _ c: Int) -> NSRect {
        if widths.count != model.columns.count { layoutCells() }
        let cell = model.cell(row: r, column: c)
        let w = (c..<min(c + cell.colspan, widths.count)).reduce(0) { $0 + widths[$1] }
        return NSRect(x: lefts[c], y: top(r), width: w, height: y(min(r + cell.rowspan, model.rowCount)) - y(r))
    }

    private enum Zone { case corner, column(Int), columnEdge(Int), row(Int), cell(Int, Int), none }

    private func zone(at p: NSPoint) -> Zone {
        let inBar = p.y < visible.minY + Self.bar, inGutter = p.x < visible.minX + Self.gutter
        if inBar && inGutter { return .corner }
        if inBar {
            if let edge = lefts.indices.first(where: { abs(lefts[$0] + widths[$0] - p.x) <= 4 }) { return .columnEdge(edge) }
            return column(at: p.x).map(Zone.column) ?? .none
        }
        guard let r = row(at: p.y) else { return .none }
        if inGutter { return .row(r) }
        return column(at: p.x).map { .cell(r, $0) } ?? .none
    }

    private func column(at x: CGFloat) -> Int? { lefts.indices.first { x >= lefts[$0] && x < lefts[$0] + widths[$0] } }

    private func row(at y: CGFloat) -> Int? {
        if model.headerRows > 0, y >= visible.minY + Self.bar, y < visible.minY + Self.bar + headerHeight { return 0 }
        guard y >= Self.bar else { return nil }
        let r = rowIndex(y - Self.bar)
        return r >= model.headerRows && r < model.rowCount ? r : nil
    }

    // MARK: drawing

    override func draw(_ dirtyRect: NSRect) {
        if columnsStale { layoutCells() }            // the model can change before SwiftUI's update reaches `refresh`
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()
        guard !widths.isEmpty else { return }
        let sel = state.selection, single = state.isSingleCell
        let firstBody = max(model.headerRows, rowIndex(visible.minY) - 1)
        let lastBody = min(model.rowCount - 1, rowIndex(visible.maxY - Self.bar))
        // Body rows (a merged cell above the view still reaches in), then the pinned header over them.
        if firstBody <= lastBody {
            for r in 0...lastBody where r >= model.headerRows { drawRow(r, sel: sel, single: single, from: firstBody) }
        }
        if model.headerRows > 0 {
            NSColor.textBackgroundColor.setFill()
            NSRect(x: visible.minX, y: top(0), width: visible.width, height: headerHeight).fill()
            drawRow(0, sel: sel, single: single, from: 0)
        }
        drawActive()
        drawBar(sel)
        drawGutter(sel)
        // Corner: select all.
        NSColor.windowBackgroundColor.setFill()
        let corner = NSRect(x: visible.minX, y: visible.minY, width: Self.gutter, height: Self.bar)
        corner.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: corner.maxX - 1, y: corner.minY, width: 1, height: corner.height).fill()
        NSRect(x: corner.minX, y: corner.maxY - 1, width: corner.width, height: 1).fill()
        if let drop { drawDrop(drop) }
    }

    private func drawRow(_ r: Int, sel: (rows: ClosedRange<Int>, columns: ClosedRange<Int>), single: Bool, from: Int) {
        let header = r < model.headerRows
        for c in model.columns.indices {
            let cell = model.cell(row: r, column: c)
            guard !cell.covered, r + cell.rowspan > from || header else { continue }
            let box = rect(r, c)
            guard box.intersects(visible) else { continue }
            if let fill = model.shownFill(row: r, column: c) {
                fillColor(fill).setFill()
                box.fill()
            }
            if header {
                NSColor.controlAccentColor.withAlphaComponent(0.10).setFill()
                box.fill()
            }
            if sel.rows.contains(r) && sel.columns.contains(c) && !single {
                NSColor.selectedContentBackgroundColor.withAlphaComponent(0.18).setFill()
                box.fill()
            } else if single && sel.rows.contains(r) && sel.columns.contains(c) {
                NSColor.controlAccentColor.withAlphaComponent(0.06).setFill()
                box.fill()
            }
            NSColor.separatorColor.setFill()
            NSRect(x: box.maxX - 1, y: box.minY, width: 1, height: box.height).fill()
            NSRect(x: box.minX, y: box.maxY - 1, width: box.width, height: header ? 1.5 : 1).fill()
            if editing.map({ $0.row == r && $0.column == c }) == true { continue }
            let vertical = cell.rowspan > 1 ? model.columns[c].vertical : nil
            if let image = images[cell.text] {
                drawImage(image, in: box.insetBy(dx: 7, dy: 1), align: model.columns[c].horizontal, vertical: vertical)
            } else {
                drawText(cell.text, in: box.insetBy(dx: 7, dy: 0), header: header, align: model.columns[c].horizontal, vertical: vertical)
            }
        }
    }

    /// An unreadable fill (a gradient) gets a neutral tint; dark mode tones fills down under the light cell text.
    private func fillColor(_ fill: String) -> NSColor {
        let c = fills[fill] ?? TableFill.color(fill).map { NSColor(srgbRed: $0.red, green: $0.green, blue: $0.blue, alpha: $0.alpha) }
            ?? NSColor.tertiaryLabelColor.withAlphaComponent(0.12)
        fills[fill] = c
        return effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? c.withAlphaComponent(c.alphaComponent * 0.35) : c
    }

    /// The cell as Typst renders it, at its own size (rendered at the grid's text size); too wide, it is cut with an ellipsis.
    private func drawImage(_ image: NSImage, in box: NSRect, align: String?, vertical: String?) {
        let size = image.size, over = size.width > box.width
        let aligned: CGFloat = switch align { case "center": box.midX - size.width / 2; case "right", "end": box.maxX - size.width; default: box.minX }
        let x = over ? box.minX : aligned
        let y: CGFloat = switch vertical { case "top": box.minY + 3; case "bottom": box.maxY - size.height - 3; default: box.midY - size.height / 2 }
        NSGraphicsContext.saveGraphicsState()
        NSRect(x: box.minX, y: box.minY, width: over ? box.width - 12 : box.width, height: box.height).clip()
        image.draw(in: NSRect(origin: NSPoint(x: x, y: y), size: size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
        if over {
            ("…" as NSString).draw(at: NSPoint(x: box.maxX - 11, y: box.midY - 8), withAttributes: [.font: font(header: false), .foregroundColor: NSColor.secondaryLabelColor])
        }
    }

    private func drawText(_ text: String, in box: NSRect, header: Bool, align: String?, vertical: String?) {
        guard !text.isEmpty else { return }
        let s = NSMutableAttributedString(attributedString: highlighted(text, header: header))
        let p = NSMutableParagraphStyle()
        p.lineBreakMode = .byTruncatingTail
        p.alignment = switch align { case "center": .center; case "right", "end": .right; default: .natural }
        s.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: s.length))
        let h = ceil(font(header: header).ascender - font(header: header).descender) + 2
        let y: CGFloat = switch vertical { case "top": box.minY + 4; case "bottom": box.maxY - h - 4; default: box.midY - h / 2 }
        s.draw(with: NSRect(x: box.minX, y: y, width: box.width, height: h), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    /// Typst markup coloured like the editor, in the sheet's font; plain words skip the parse.
    private func highlighted(_ text: String, header: Bool) -> NSAttributedString {
        let key = (header ? "1" : "0") + text
        if let s = styled[key] { return s }
        let line = text.replacingOccurrences(of: "\n", with: " ")
        let s: NSMutableAttributedString
        if line.contains(where: { "#$*_@<`\\=-+/[]".contains($0) }) {
            s = NSMutableAttributedString(attributedString: Highlighter.attributed(line, path: "cell.typ"))
            let base = Highlighter.base[.foregroundColor] as? NSColor
            s.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: s.length)) { value, range, _ in
                if (value as? NSColor) == base || value == nil { s.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range) }
            }
        } else {
            s = NSMutableAttributedString(string: line, attributes: [.foregroundColor: NSColor.labelColor])
        }
        s.addAttribute(.font, value: font(header: header), range: NSRange(location: 0, length: s.length))
        if styled.count > 2000 { styled.removeAll() }
        styled[key] = s
        return s
    }

    private func drawActive() {
        guard editing == nil, model.rowCount > 0, !model.columns.isEmpty else { return }
        let box = rect(state.cursor.row, state.cursor.column).insetBy(dx: 0.5, dy: 0.5)
        guard state.cursor.row < model.headerRows || box.maxY > visible.minY + Self.bar + headerHeight else { return }
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: box.insetBy(dx: 0.5, dy: 0.5))
        path.lineWidth = 2
        path.stroke()
    }

    private func drawBar(_ sel: (rows: ClosedRange<Int>, columns: ClosedRange<Int>)) {
        let barRect = NSRect(x: visible.minX, y: visible.minY, width: visible.width, height: Self.bar)
        NSColor.windowBackgroundColor.setFill()
        barRect.fill()
        for c in model.columns.indices {
            let box = NSRect(x: lefts[c], y: visible.minY, width: widths[c], height: Self.bar)
            guard box.intersects(visible) else { continue }
            if sel.columns.contains(c) {
                NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
                box.fill()
            }
            NSColor.separatorColor.setFill()
            NSRect(x: box.maxX - 1, y: box.minY, width: 1, height: box.height).fill()
            let label = Self.columnName(c)
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium),
                                                        .foregroundColor: sel.columns.contains(c) ? NSColor.labelColor : NSColor.secondaryLabelColor]
            let size = (label as NSString).size(withAttributes: attrs)
            (label as NSString).draw(at: NSPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2), withAttributes: attrs)
            if let symbol = NSImage(systemSymbolName: Self.alignSymbol(model.columns[c].horizontal), accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 9, weight: .regular)), box.width > 50 {
                let tinted = symbol.tinted(.tertiaryLabelColor)
                tinted.draw(in: NSRect(x: box.maxX - symbol.size.width - 6, y: box.midY - symbol.size.height / 2, width: symbol.size.width, height: symbol.size.height))
            }
        }
        NSColor.separatorColor.setFill()
        NSRect(x: barRect.minX, y: barRect.maxY - 1, width: barRect.width, height: 1).fill()
    }

    private func drawGutter(_ sel: (rows: ClosedRange<Int>, columns: ClosedRange<Int>)) {
        let g = NSRect(x: visible.minX, y: visible.minY, width: Self.gutter, height: visible.height)
        NSColor.windowBackgroundColor.setFill()
        g.fill()
        let attrs: (Bool) -> [NSAttributedString.Key: Any] = { on in
            [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium),
             .foregroundColor: on ? NSColor.labelColor : NSColor.secondaryLabelColor]
        }
        // The header last: it covers body rows scrolled under it.
        for r in Array(model.headerRows..<model.rowCount) + Array(0..<model.headerRows) {
            let box = NSRect(x: visible.minX, y: top(r), width: Self.gutter, height: y(r + 1) - y(r))
            guard box.intersects(visible) else { continue }
            NSColor.windowBackgroundColor.setFill()
            box.fill()
            if sel.rows.contains(r) {
                NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
                box.fill()
            }
            NSColor.separatorColor.setFill()
            NSRect(x: box.minX, y: box.maxY - 1, width: box.width, height: 1).fill()
            let label = Self.rowName(r, headerRows: model.headerRows) as NSString
            let a = attrs(sel.rows.contains(r))
            let size = label.size(withAttributes: a)
            label.draw(at: NSPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2), withAttributes: a)
        }
        NSColor.separatorColor.setFill()
        NSRect(x: g.maxX - 1, y: g.minY, width: 1, height: g.height).fill()
    }

    private func drawDrop(_ d: (column: Bool, at: Int)) {
        NSColor.controlAccentColor.setFill()
        if d.column {
            let x = d.at < lefts.count ? lefts[d.at] : (lefts.last ?? Self.gutter) + (widths.last ?? 0)
            NSRect(x: x - 1.5, y: visible.minY, width: 3, height: visible.height).fill()
        } else {
            NSRect(x: visible.minX, y: top(d.at) - 1.5, width: visible.width, height: 3).fill()
        }
    }

    static func columnName(_ c: Int) -> String {
        var n = c, s = ""
        repeat { s = String(UnicodeScalar(UInt8(65 + n % 26))) + s; n = n / 26 - 1 } while n >= 0
        return s
    }

    static func rowName(_ r: Int, headerRows: Int) -> String { r < headerRows ? "H" : "\(r - headerRows + 1)" }

    static func alignSymbol(_ h: String?) -> String {
        switch h { case "center": "text.aligncenter"; case "right", "end": "text.alignright"; default: "text.alignleft" }
    }

    // MARK: mouse

    override func mouseDown(with event: NSEvent) {
        commitEdit()
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        let extend = event.modifierFlags.contains(.shift)
        switch zone(at: p) {
        case .corner: state.selectAll()
        case .columnEdge(let c): resizeColumn(c, from: event)
        case .column(let c):
            // The alignment icon at the right of the column bar cycles left, center, right.
            if widths[c] > 50, p.x >= lefts[c] + widths[c] - 22, !extend { state.cycleAlignment(column: c); refresh(); return }
            if extend { state.selectColumns(min(c, state.anchor.column)...max(c, state.anchor.column)) } else { state.selectColumns(c...c) }
            reorder(column: true, from: c, event: event)
        case .row(let r):
            if extend { state.selectRows(min(r, state.anchor.row)...max(r, state.anchor.row)) } else { state.selectRows(r...r) }
            if r >= model.headerRows { reorder(column: false, from: r, event: event) }
        case .cell(let r, let c):
            if event.clickCount == 2 { state.select(.init(row: r, column: c)); beginEdit(replacing: false); return }
            state.select(.init(row: r, column: c), extend: extend)
            refresh()
            trackSelection(event)
        case .none: break
        }
    }

    private func trackSelection(_ down: NSEvent) {
        while let e = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]), e.type == .leftMouseDragged {
            autoscroll(with: e)
            let p = convert(e.locationInWindow, from: nil)
            if let r = row(at: p.y) ?? (p.y < Self.bar ? model.headerRows : nil), let c = column(at: p.x) {
                state.select(.init(row: r, column: c), extend: true)
                refresh()                               // SwiftUI does not update during the tracking loop
            }
        }
    }

    private func resizeColumn(_ c: Int, from down: NSEvent) {
        let start = convert(down.locationInWindow, from: nil).x, startWidth = widths[c]
        let original = model.columns[c].width
        var last = original
        NSCursor.resizeLeftRight.push()
        defer { NSCursor.pop() }
        state.undo.beginUndoGrouping()
        defer { state.undo.endUndoGrouping() }
        while let e = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]), e.type == .leftMouseDragged {
            let w = max(Self.minColumn, startWidth + convert(e.locationInWindow, from: nil).x - start)
            // A fraction column stays a fraction; anything else becomes a fixed width in points.
            let width: ColumnWidth = if case .fraction = original { .fraction((w / 110 * 10).rounded() / 10) } else { .points((w / 1.25).rounded()) }
            guard width != last else { continue }
            last = width
            state.setWidth(width, columns: c...c)
            refresh()
        }
    }

    private func reorder(column: Bool, from: Int, event: NSEvent) {
        let start = convert(event.locationInWindow, from: nil)
        var moved = false
        while let e = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let p = convert(e.locationInWindow, from: nil)
            if e.type == .leftMouseUp { break }
            autoscroll(with: e)
            if !moved && hypot(p.x - start.x, p.y - start.y) < 4 { continue }
            moved = true
            if column {
                let at = lefts.indices.first { p.x < lefts[$0] + widths[$0] / 2 } ?? lefts.count
                drop = (true, at)
            } else {
                let offset = p.y - Self.bar, i = min(rowIndex(offset), model.rowCount - 1)
                let r = offset > (y(i) + y(i + 1)) / 2 ? i + 1 : i
                drop = (false, min(max(r, model.headerRows), model.rowCount))
            }
            needsDisplay = true
        }
        guard let d = drop else { return }
        drop = nil
        needsDisplay = true
        // `at` is a boundary; the move APIs take the index after the move.
        let to = d.at > from ? d.at - 1 : d.at
        guard to != from else { return }
        if d.column { state.moveColumn(from: from, to: to) } else { state.moveRow(from: from, to: to) }
    }

    override func resetCursorRects() {
        for c in lefts.indices {
            addCursorRect(NSRect(x: lefts[c] + widths[c] - 4, y: visible.minY, width: 8, height: Self.bar), cursor: .resizeLeftRight)
        }
    }

    // MARK: context menus

    override func menu(for event: NSEvent) -> NSMenu? {
        commitEdit()
        let p = convert(event.locationInWindow, from: nil)
        let sel = state.selection
        switch zone(at: p) {
        case .column(let c), .columnEdge(let c):
            if !sel.columns.contains(c) || sel.rows.count < model.rowCount { state.selectColumns(c...c) }
            return columnMenu()
        case .row(let r):
            if !sel.rows.contains(r) || sel.columns.count < model.columns.count { state.selectRows(r...r) }
            return rowMenu()
        case .cell(let r, let c):
            if !(sel.rows.contains(r) && sel.columns.contains(c)) { state.select(.init(row: r, column: c)) }
            return cellMenu()
        case .corner, .none: return nil
        }
    }

    private func item(_ title: String, _ symbol: String? = nil, enabled: Bool = true, on: Bool = false, _ action: @escaping () -> Void) -> NSMenuItem {
        let i = ActionMenuItem(title: title) { [weak self] in action(); self?.refresh() }
        if let symbol { i.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        i.isEnabled = enabled
        i.state = on ? .on : .off
        return i
    }

    private func menu(_ items: [NSMenuItem]) -> NSMenu {
        let m = NSMenu()
        m.autoenablesItems = false
        items.forEach(m.addItem)
        return m
    }

    private func columnMenu() -> NSMenu {
        let cols = state.selectedColumns, c = cols.lowerBound
        let spec = model.columns[c]
        let width = spec.width
        let widthItems: [NSMenuItem] = [
            item("Auto", on: width == .auto) { [state] in state.setWidth(.auto, columns: cols) },
            item("1fr (share the rest)", on: width == .fraction(1)) { [state] in state.setWidth(.fraction(1), columns: cols) },
            item("2fr", on: width == .fraction(2)) { [state] in state.setWidth(.fraction(2), columns: cols) },
            item("Fixed: \(ColumnWidth.points(width.points(fallback: widths[c] / 1.25)).size!)", on: { if case .points = width { true } else { false } }()) { [state, widths] in
                state.setWidth(.points((widths[c] / 1.25).rounded()), columns: cols)
            },
        ]
        let widthMenu = NSMenuItem(title: "Width: \(spec.size ?? "auto")", action: nil, keyEquivalent: "")
        widthMenu.image = NSImage(systemSymbolName: "arrow.left.and.right", accessibilityDescription: nil)
        widthMenu.submenu = menu(widthItems)
        return menu(alignmentItems(spec) + [.separator(), widthMenu, .separator(),
            item("Insert Column Left", "arrow.left.to.line") { [state] in state.insertColumns(left: true) },
            item("Insert Column Right", "arrow.right.to.line") { [state] in state.insertColumns(left: false) },
            item("Duplicate Column", "plus.square.on.square") { [state] in state.duplicateColumns() },
            item("Move Left", "arrow.left", enabled: c > 0 && cols.count == 1) { [state] in state.moveColumn(from: c, to: c - 1) },
            item("Move Right", "arrow.right", enabled: cols.upperBound < model.columns.count - 1 && cols.count == 1) { [state] in state.moveColumn(from: c, to: c + 1) },
            .separator(),
            item("Clear", "eraser") { [state] in state.clearSelection() },
            item(cols.count > 1 ? "Delete Columns" : "Delete Column", "trash", enabled: cols.count < model.columns.count) { [state] in state.deleteColumns() },
        ])
    }

    private func alignmentItems(_ spec: ColumnSpec) -> [NSMenuItem] {
        let enabled = model.alignEditable
        let h: [NSMenuItem] = [("Align Left", "left", "text.alignleft"), ("Align Center", "center", "text.aligncenter"), ("Align Right", "right", "text.alignright")].map { t, v, s in
            item(t, s, enabled: enabled, on: spec.horizontal == v) { [state] in state.setHorizontal(spec.horizontal == v ? nil : v) }
        }
        let v: [NSMenuItem] = [("Top", "top", "arrow.up.to.line"), ("Middle", "horizon", "arrow.up.and.down"), ("Bottom", "bottom", "arrow.down.to.line")].map { t, v, s in
            item(t, s, enabled: enabled, on: spec.vertical == v) { [state] in state.setVertical(spec.vertical == v ? nil : v) }
        }
        let vMenu = NSMenuItem(title: "Vertical Alignment", action: nil, keyEquivalent: "")
        vMenu.submenu = menu(v)
        vMenu.isEnabled = enabled
        return h + [vMenu]
    }

    private func rowMenu() -> NSMenu {
        let rows = state.selection.rows, r = rows.lowerBound, hr = model.headerRows
        let isHeader = r < hr
        return menu([
            item("Header Row", "tablecells", on: hr > 0) { [state] in state.toggleHeader() },
            .separator(),
            item("Insert Row Above", "arrow.up.to.line", enabled: !isHeader) { [state] in state.insertRows(above: true) },
            item("Insert Row Below", "arrow.down.to.line") { [state] in state.insertRows(above: false) },
            item("Duplicate Row", "plus.rectangle.on.rectangle") { [state] in state.duplicateRows() },
            item("Move Up", "arrow.up", enabled: !isHeader && r > hr && rows.count == 1) { [state] in state.moveRow(from: r, to: r - 1) },
            item("Move Down", "arrow.down", enabled: !isHeader && rows.upperBound < model.rowCount - 1 && rows.count == 1) { [state] in state.moveRow(from: r, to: r + 1) },
            .separator(),
            item("Clear", "eraser") { [state] in state.clearSelection() },
            item(isHeader && rows.count == 1 ? "Remove Header" : rows.count > 1 ? "Delete Rows" : "Delete Row", "trash") { [state] in state.deleteRows() },
        ])
    }

    private func cellMenu() -> NSMenu {
        let insert = NSMenuItem(title: "Insert", action: nil, keyEquivalent: "")
        insert.submenu = menu([
            item("Row Above", "arrow.up.to.line", enabled: state.selection.rows.lowerBound >= model.headerRows) { [state] in state.insertRows(above: true) },
            item("Row Below", "arrow.down.to.line") { [state] in state.insertRows(above: false) },
            item("Column Left", "arrow.left.to.line") { [state] in state.insertColumns(left: true) },
            item("Column Right", "arrow.right.to.line") { [state] in state.insertColumns(left: false) },
        ])
        let delete = NSMenuItem(title: "Delete", action: nil, keyEquivalent: "")
        delete.submenu = menu([
            item("Row", "trash") { [state] in state.deleteRows() },
            item("Column", "trash", enabled: state.selection.columns.count < model.columns.count) { [state] in state.deleteColumns() },
        ])
        return menu([
            item("Cut", "scissors") { [weak self] in self?.cut(nil) },
            item("Copy", "doc.on.doc") { [weak self] in self?.copy(nil) },
            item("Paste", "doc.on.clipboard", enabled: NSPasteboard.general.string(forType: .string) != nil) { [weak self] in self?.paste(nil) },
            item("Clear", "eraser") { [state] in state.clearSelection() },
            .separator(),
            item("Bold", "bold") { [state] in state.toggleEmphasis("*") },
            item("Italic", "italic") { [state] in state.toggleEmphasis("_") },
            .separator(),
            item("Merge Cells", "rectangle.split.2x1.slash", enabled: state.canMerge) { [state] in state.mergeSelection() },
            item("Unmerge Cells", "rectangle.split.2x1", enabled: state.canUnmerge) { [state] in state.unmergeSelection() },
            .separator(),
            insert, delete,
        ])
    }

    // MARK: keyboard

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .control, .option])
        if mods.subtracting(.option).isEmpty, let chars = event.characters, let u = chars.unicodeScalars.first,
           !(0xF700...0xF8FF).contains(u.value), u.value >= 0x20, u.value != 0x7F {
            beginEdit(replacing: true, forward: event)
            return
        }
        interpretKeyEvents([event])
    }

    private func step(_ dr: Int, _ dc: Int, extend: Bool) {
        let from = state.cursor
        // Skip over the rest of a merged cell.
        let cell = model.cell(row: from.row, column: from.column)
        var r = from.row + dr, c = from.column + dc
        if !extend {
            if dr > 0 { r = from.row + max(1, cell.rowspan) }
            if dc > 0 { c = from.column + max(1, cell.colspan) }
        }
        guard r >= 0, r < model.rowCount, c >= 0, c < model.columns.count else { return }
        state.select(.init(row: r, column: c), extend: extend)
        scrollToCursor()
    }

    override func moveUp(_ sender: Any?) { step(-1, 0, extend: false) }
    override func moveDown(_ sender: Any?) { step(1, 0, extend: false) }
    override func moveLeft(_ sender: Any?) { step(0, -1, extend: false) }
    override func moveRight(_ sender: Any?) { step(0, 1, extend: false) }
    override func moveUpAndModifySelection(_ sender: Any?) { step(-1, 0, extend: true) }
    override func moveDownAndModifySelection(_ sender: Any?) { step(1, 0, extend: true) }
    override func moveLeftAndModifySelection(_ sender: Any?) { step(0, -1, extend: true) }
    override func moveRightAndModifySelection(_ sender: Any?) { step(0, 1, extend: true) }
    override func moveToBeginningOfDocument(_ sender: Any?) { state.select(.init(row: 0, column: 0)); scrollToCursor() }
    override func moveToEndOfDocument(_ sender: Any?) { state.select(.init(row: model.rowCount - 1, column: model.columns.count - 1)); scrollToCursor() }
    override func insertNewline(_ sender: Any?) { beginEdit(replacing: false) }
    override func insertTab(_ sender: Any?) { tab(1) }
    override func insertBacktab(_ sender: Any?) { tab(-1) }
    override func deleteBackward(_ sender: Any?) { state.deleteSelection() }
    override func deleteForward(_ sender: Any?) { state.deleteSelection() }
    override func cancelOperation(_ sender: Any?) { onCancel() }
    override func selectAll(_ sender: Any?) { state.selectAll() }

    /// Tab walks the cells in reading order and wraps at the row ends.
    private func tab(_ dir: Int) {
        let n = model.columns.count
        var i = state.cursor.row * n + state.cursor.column
        repeat { i += dir } while i >= 0 && i < model.rowCount * n && model.cell(row: i / n, column: i % n).covered
        if dir > 0, i >= model.rowCount * n { state.appendRow(); scrollToCursor(); return }
        guard i >= 0, i < model.rowCount * n else { return }
        state.select(.init(row: i / n, column: i % n))
        scrollToCursor()
    }

    private func scrollToCursor() {
        var r = rect(state.cursor.row, state.cursor.column)
        if state.cursor.row >= model.headerRows { r.origin.y -= Self.bar + headerHeight; r.size.height += Self.bar + headerHeight }
        r.origin.x -= Self.gutter
        r.size.width += Self.gutter
        scrollToVisible(r)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers {
        case "b": state.toggleEmphasis("*"); return true
        case "i": state.toggleEmphasis("_"); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }

    // MARK: pasteboard and undo

    static let cellsType = NSPasteboard.PasteboardType("com.tympan.table-cells")

    @objc func copy(_ sender: Any?) {
        let tsv = TableClipboard.tsv(state.selectedTexts)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(tsv, forType: .string)
        pb.setString(tsv, forType: Self.cellsType)            // our own copy keeps the markup as written
    }

    @objc func cut(_ sender: Any?) {
        copy(sender)
        state.clearSelection()
        state.undo.setActionName("Cut")
    }

    @objc func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        if let own = pb.string(forType: Self.cellsType) {
            state.paste(TableClipboard.parse(own))
        } else if let plain = pb.string(forType: .string) {
            state.paste(TableClipboard.parse(plain).map { $0.map(TableClipboard.markup) })
        }
    }

    /// While a cell is being edited, undo is the typing in it; otherwise the sheet's history.
    private var activeUndo: UndoManager { editing != nil ? editor.typing : state.undo }

    @objc func undo(_ sender: Any?) { activeUndo.undo() }
    @objc func redo(_ sender: Any?) { activeUndo.redo() }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(undo(_:)):
            item.title = activeUndo.undoMenuItemTitle
            return activeUndo.canUndo
        case #selector(redo(_:)):
            item.title = activeUndo.redoMenuItemTitle
            return activeUndo.canRedo
        case #selector(paste(_:)): return NSPasteboard.general.string(forType: .string) != nil
        default: return true
        }
    }

    // MARK: editing a cell

    private func beginEdit(replacing: Bool, forward event: NSEvent? = nil) {
        guard model.rowCount > 0 else { return }
        let p = state.cursor
        editing = p
        editor.typing.removeAllActions()
        editor.stringValue = replacing ? "" : model.cell(row: p.row, column: p.column).text
        editor.font = font(header: p.row < model.headerRows)
        editor.alignment = switch model.columns[p.column].horizontal { case "center": .center; case "right", "end": .right; default: .natural }
        addSubview(editor)
        placeEditor(p)
        window?.makeFirstResponder(editor)
        if let tv = editor.currentEditor() {
            tv.selectedRange = NSRange(location: (tv.string as NSString).length, length: 0)
            if let event { tv.keyDown(with: event) }        // the field editor turns the key into text (dead keys too)
        }
        needsDisplay = true
    }

    /// The field sits on the cell and grows to the right (and over the view's width) for longer text.
    private func placeEditor(_ p: TableSheetState.Point) {
        guard p.row < model.rowCount, p.column < model.columns.count else { return }
        var box = rect(p.row, p.column)
        let text = (editor.stringValue as NSString).size(withAttributes: [.font: editor.font ?? font(header: false)]).width + 24
        box.size.width = min(max(box.width, text), max(box.width, visible.maxX - box.minX))
        box.size.height = max(box.height, Self.rowHeight)
        editor.frame = box
    }

    /// Writes the field into the model (one undo step) and leaves edit mode.
    /// `refocus` false when focus is going elsewhere (a click in the caption field).
    @discardableResult
    func commitEdit(refocus: Bool = true) -> Bool {
        guard let p = editing else { return false }
        editing = nil
        popup.hide()
        let text = editor.stringValue
        if refocus { window?.makeFirstResponder(self) }
        editor.removeFromSuperview()
        if text != model.cell(row: p.row, column: p.column).text { state.setText(text, at: p) }
        needsDisplay = true
        return true
    }

    private func cancelEdit() {
        editing = nil
        popup.hide()
        window?.makeFirstResponder(self)
        editor.removeFromSuperview()
        needsDisplay = true
    }

    func controlTextDidChange(_ note: Notification) {
        if let e = editing { placeEditor(e) }
        if !accepting { refreshCompletion(in: note.userInfo?["NSFieldEditor"] as? NSTextView) }
    }

    func controlTextDidEndEditing(_ note: Notification) {
        // Focus moved elsewhere (Return, Tab and Esc have already left edit mode): keep what was typed.
        if editing != nil { commitEdit(refocus: false) }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if popup.isVisible {
            switch sel {
            case #selector(NSResponder.moveUp(_:)): popup.move(by: -1)
            case #selector(NSResponder.moveDown(_:)): popup.move(by: 1)
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
                if let item = popup.selected { accept(item) }
            case #selector(NSResponder.cancelOperation(_:)): popup.hide()
            case #selector(NSResponder.moveLeft(_:)), #selector(NSResponder.moveRight(_:)): popup.hide(); return false
            default: return false
            }
            return true
        }
        switch sel {
        case #selector(NSResponder.insertNewline(_:)):
            commitEdit()
            let c = state.cursor
            if c.row + model.cell(row: c.row, column: c.column).rowspan >= model.rowCount {
                state.appendRow()
                state.select(.init(row: model.rowCount - 1, column: c.column))
                scrollToCursor()
            } else {
                step(1, 0, extend: false)
            }
        case #selector(NSResponder.insertTab(_:)): commitEdit(); tab(1)
        case #selector(NSResponder.insertBacktab(_:)): commitEdit(); tab(-1)
        case #selector(NSResponder.cancelOperation(_:)): cancelEdit()
        default: return false
        }
        return true
    }

    private func refreshCompletion(in tv: NSTextView?) {
        generation += 1
        guard let tv, let p = editing, tv.selectedRange().length == 0,
              let r = CellCompletion.request(in: tv.string, caret: tv.selectedRange().location) else { return popup.hide() }
        let id = generation, text = tv.string, caret = tv.selectedRange().location
        Task { [weak self, weak tv] in
            guard let self else { return }
            let items = await complete?(p.row, p.column, text, caret, r) ?? completions.items(for: r)
            // A newer keystroke or a closed field makes this answer stale.
            guard id == generation, let tv, tv.string == text, tv.selectedRange().location == caret else { return }
            guard !items.isEmpty else { return popup.hide() }
            request = r
            popup.show(items, range: r.range, in: tv)
        }
    }

    private func accept(_ item: CompletionItem) {
        guard let tv = editor.currentEditor() as? NSTextView, let r = request else { return }
        accepting = true
        tv.insertText(item.apply ?? item.label, replacementRange: r.range)
        accepting = false
        popup.hide()
        if let e = editing { placeEditor(e) }
    }

    // MARK: accessibility

    override func accessibilityRowCount() -> Int { model.rowCount }
    override func accessibilityColumnCount() -> Int { model.columns.count }
    override func accessibilityChildren() -> [Any]? { allCells() }
    override func accessibilityVisibleCells() -> [Any]? { allCells() }
    override func accessibilitySelectedCells() -> [Any]? {
        let s = state.selection
        return s.rows.flatMap { r in s.columns.compactMap { c in model.cell(row: r, column: c).covered ? nil : element(r, c) } }
    }
    override func accessibilityCell(forColumn column: Int, row: Int) -> Any? {
        guard row < model.rowCount, column < model.columns.count else { return nil }
        let a = model.anchor(row: row, column: column)
        return element(a.row, a.column)
    }

    private func allCells() -> [Any] {
        (0..<model.rowCount).flatMap { r in model.columns.indices.compactMap { c in model.cell(row: r, column: c).covered ? nil : element(r, c) } }
    }

    private func element(_ r: Int, _ c: Int) -> GridCellElement {
        let key = TableSheetState.Point(row: r, column: c)
        let e = cellElements[key] ?? GridCellElement()
        cellElements[key] = e
        let cell = model.cell(row: r, column: c), d = accessibilityDescription(row: r, column: c), s = state.selection
        e.setAccessibilityRole(.cell)
        e.setAccessibilityParent(self)
        e.setAccessibilityLabel(d.label)
        e.setAccessibilityValue(d.value)
        e.setAccessibilityRowIndexRange(NSRange(location: r, length: cell.rowspan))
        e.setAccessibilityColumnIndexRange(NSRange(location: c, length: cell.colspan))
        e.setAccessibilityFrameInParentSpace(rect(r, c))
        e.setAccessibilitySelected(s.rows.contains(r) && s.columns.contains(c))
        return e
    }

    func accessibilityDescription(row r: Int, column c: Int) -> (label: String, value: String) {
        let header = model.headerRows > 0 && r > 0 ? model.cell(row: 0, column: c).text : ""
        let name = "\(Self.columnName(c))\(Self.rowName(r, headerRows: model.headerRows))"
        return (header.isEmpty ? name : "\(name), \(header)", model.cell(row: r, column: c).text)
    }
}

/// One cell for VoiceOver; the grid fills in its place, label and text whenever it is asked for.
final class GridCellElement: NSAccessibilityElement {}

/// The text field that edits the active cell: flat, on the cell, with the accent focus ring.
final class CellEditorField: NSTextField {
    /// The field editor asks its next responder (this field) for an undo manager: typing stays out of the sheet's history.
    let typing = UndoManager()
    override var undoManager: UndoManager? { typing }

    init() {
        super.init(frame: .zero)
        isBezeled = false
        isBordered = false
        drawsBackground = true
        backgroundColor = .textBackgroundColor
        focusRingType = .exterior
        usesSingleLineMode = true
        cell?.isScrollable = true
        cell?.wraps = false
        lineBreakMode = .byClipping
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// A menu item that runs a closure.
final class ActionMenuItem: NSMenuItem {
    private let run: () -> Void

    init(title: String, action: @escaping () -> Void) {
        run = action
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { run() }
}

extension ColumnWidth {
    /// The width in points this column has, or `fallback` when it is not fixed.
    func points(fallback: CGFloat) -> Double {
        if case .points(let v) = self { return v }
        return Double(fallback.rounded())
    }
}

extension NSImage {
    func tinted(_ color: NSColor) -> NSImage {
        let image = copy() as! NSImage
        image.lockFocus()
        color.set()
        NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
        image.unlockFocus()
        return image
    }
}

/// Makes the sheet window resizable and remembers its size.
enum TableSheetWindow {
    static let key = "TableEditorSheetSize"
    static let minSize = NSSize(width: 780, height: 420)    // the compact format bar fits
    @MainActor private static var observed = Set<ObjectIdentifier>()

    private static var saved: NSSize? {
        UserDefaults.standard.string(forKey: key).map(NSSizeFromString).flatMap { $0.width >= minSize.width && $0.height >= minSize.height ? $0 : nil }
    }

    @MainActor static func adopt(_ window: NSWindow?) {
        guard let window, window.isSheet, !observed.contains(ObjectIdentifier(window)) else { return }
        observed.insert(ObjectIdentifier(window))
        window.styleMask.insert(.resizable)
        window.contentMinSize = minSize
        window.setContentSize(saved ?? NSSize(width: 1080, height: 660))
        NotificationCenter.default.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: window, queue: .main) { n in
            guard let w = n.object as? NSWindow else { return }
            MainActor.assumeIsolated {                    // delivered on the main queue
                guard let size = w.contentView?.frame.size else { return }
                UserDefaults.standard.set(NSStringFromSize(size), forKey: key)
            }
        }
    }
}
