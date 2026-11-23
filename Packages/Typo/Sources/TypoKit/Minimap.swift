import Foundation

/// The minimap's picture of a document (as in Xcode): one entry per shown line with its colour runs, so drawing
/// needs neither the text nor its layout. Built off the main actor from a snapshot of the buffer.
public struct MinimapModel: Equatable, Sendable {
    /// Characters `range` of the text carry palette colour `color` (the app keeps the palette).
    public struct ColorRun: Equatable, Sendable {
        public let range: NSRange
        public let color: Int
        public init(range: NSRange, color: Int) { self.range = range; self.color = color }
    }

    /// Columns `column..<column+length` of a line in one colour; blanks inside a run are part of it.
    public struct Run: Equatable, Sendable {
        public let column: Int
        public let length: Int
        public let color: Int
    }

    public struct Heading: Equatable, Sendable {
        public let level: Int
        public let title: String
    }

    public struct Line: Equatable, Sendable {
        public let offset: Int       // start of the line in the text
        public let number: Int       // the line's number in the text, from 0
        public let runs: [Run]
        public let heading: Heading?
        public var indent: Int { runs.first?.column ?? 0 }
    }

    /// The shown lines: a folded section's lines are left out, its heading line stays.
    public let lines: [Line]

    public init(lines: [Line] = []) { self.lines = lines }

    /// One line per line of `text` outside `hidden`; `runs` sorted by location, characters outside them get colour 0;
    /// `headings` as `Buffer.headingLines`. Tabs advance to the next multiple of `tabWidth` columns.
    public static func build(text: String, runs: [ColorRun], headings: [(line: Int, level: Int)], hidden: [NSRange], tabWidth: Int = 4) -> MinimapModel {
        let u = Array(text.utf16)
        let n = u.count
        let levels = Dictionary(headings.map { ($0.line, $0.level) }, uniquingKeysWith: { a, _ in a })
        let hidden = hidden.sorted { $0.location < $1.location }
        var out: [Line] = []
        var h = 0, r = 0, start = 0, number = 0
        while true {
            var end = start
            while end < n, u[end] != 10 { end += 1 }
            while h < hidden.count, NSMaxRange(hidden[h]) <= start, !(start == n && NSMaxRange(hidden[h]) == n) { h += 1 }
            let isHidden = h < hidden.count && (NSLocationInRange(start, hidden[h]) || (start == n && NSMaxRange(hidden[h]) == n))
            if !isHidden {
                var lineRuns: [Run] = []
                var column = 0
                for i in start..<end {
                    let c = u[i]
                    if c == 32 || c == 9 || c == 13 {
                        column = c == 9 ? (column / tabWidth + 1) * tabWidth : column + 1
                        continue
                    }
                    while r < runs.count, NSMaxRange(runs[r].range) <= i { r += 1 }
                    let color = r < runs.count && runs[r].range.location <= i ? runs[r].color : 0
                    if let last = lineRuns.last, last.color == color {
                        lineRuns[lineRuns.count - 1] = Run(column: last.column, length: column + 1 - last.column, color: color)
                    } else {
                        lineRuns.append(Run(column: column, length: 1, color: color))
                    }
                    column += 1
                }
                let heading = levels[start].map { level -> Heading in
                    let line = String(utf16CodeUnits: Array(u[start..<end]), count: end - start)
                    let title = line.drop { $0 == " " || $0 == "\t" }.drop { $0 == "=" }
                    return Heading(level: level, title: title.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                out.append(Line(offset: start, number: number, runs: lineRuns, heading: heading))
            }
            guard end < n else { break }
            start = end + 1
            number += 1
        }
        return MinimapModel(lines: out)
    }

    /// The shown line holding text position `offset`; a hidden position maps to the heading line its fold shows as.
    public func lineIndex(of offset: Int) -> Int {
        var lo = 0, hi = lines.count - 1
        guard hi > 0 else { return 0 }
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lines[mid].offset <= offset { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    /// The heading of the section shown line `index` lies in (its own, if it is a heading line).
    public func heading(containing index: Int) -> Heading? {
        guard !lines.isEmpty else { return nil }
        return lines[...min(max(index, 0), lines.count - 1)].last { $0.heading != nil }?.heading
    }
}

/// Where the minimap draws and how it scrolls. Lines sit at their index times `lineHeight` (no text layout); when they
/// do not fit in `viewHeight`, the minimap scrolls in proportion to the editor so the visible band stays on screen.
/// Editor positions are in shown lines, fractional: `top` is the first visible one, `visible` how many are on screen.
public struct MinimapGeometry: Equatable, Sendable {
    public let lineCount: Int
    public let lineHeight: CGFloat
    public let viewHeight: CGFloat

    public init(lineCount: Int, lineHeight: CGFloat, viewHeight: CGFloat) {
        self.lineCount = lineCount
        self.lineHeight = lineHeight
        self.viewHeight = viewHeight
    }

    private var overflow: CGFloat { max(0, CGFloat(lineCount) * lineHeight - viewHeight) }
    private func range(_ visible: Double) -> Double { Double(lineCount) - visible }

    /// The minimap's own scroll offset (points of its content above its top edge).
    public func offset(top: Double, visible: Double) -> CGFloat {
        guard overflow > 0, range(visible) > 0 else { return 0 }
        return overflow * CGFloat(min(max(top / range(visible), 0), 1))
    }

    /// The band showing the editor's visible lines, in view coordinates (y down).
    public func band(top: Double, visible: Double) -> (y: CGFloat, height: CGFloat) {
        (CGFloat(top) * lineHeight - offset(top: top, visible: visible), CGFloat(visible) * lineHeight)
    }

    /// The (fractional) shown line under view position `y`.
    public func line(atY y: CGFloat, top: Double, visible: Double) -> Double {
        min(max(Double((y + offset(top: top, visible: visible)) / lineHeight), 0), Double(lineCount))
    }

    /// A click at `y`: the top line that centres the clicked line in the editor.
    public func top(centering y: CGFloat, top: Double, visible: Double) -> Double {
        clampTop(line(atY: y, top: top, visible: visible) - visible / 2, visible)
    }

    /// A drag that puts the band's top edge at `bandY`: the editor's top line. The inverse of `band`, whose y is
    /// linear in `top` (the band travels the view while the editor travels the document).
    public func top(forBandY bandY: CGFloat, visible: Double) -> Double {
        let slope = Double(lineHeight) - (range(visible) > 0 ? Double(overflow) / range(visible) : 0)
        guard slope > 0.0001 else { return clampTop(Double(bandY + CGFloat(visible) * lineHeight / 2) / Double(viewHeight) * Double(lineCount) - visible / 2, visible) }
        return clampTop(Double(bandY) / slope, visible)
    }

    private func clampTop(_ t: Double, _ visible: Double) -> Double { min(max(t, 0), max(range(visible), 0)) }
}
