import Foundation
import TypstEngine
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// Indentation scope guides: where the levels of a line's leading blanks begin.
public enum ScopeGuides {
    /// UTF-16 offsets from the line start at which each level of `line`'s leading blanks begins: one level per tab or per
    /// `unit` spaces; spaces short of a level before a tab belong to that tab's level.
    public static func starts(of line: some StringProtocol, unit: Int) -> [Int] {
        var out: [Int] = [], begin = 0, spaces = 0
        for (i, c) in line.utf16.enumerated() {
            if c == 9 { out.append(begin); begin = i + 1; spaces = 0 }
            else if c == 32 { spaces += 1; if spaces == max(unit, 1) { out.append(begin); begin = i + 1; spaces = 0 } }
            else { break }
        }
        return out
    }

    /// The level of each line starting at `lineStarts`; a blank line takes the smaller level of the nearest non-blank
    /// lines above and below (none counts as 0), so it continues the guides of the block it sits in.
    public static func levels(in text: NSString, lineStarts: [Int], unit: Int) -> [Int] {
        var cache: [Int: Int?] = [:]
        func own(_ start: Int) -> Int? {          // nil for a blank line
            if let c = cache[start] { return c }
            let line = text.substring(with: text.lineRange(for: NSRange(location: start, length: 0)))
            let v: Int? = line.allSatisfy { $0.isWhitespace } ? nil : starts(of: line, unit: unit).count
            cache[start] = v
            return v
        }
        func nearest(from start: Int, up: Bool) -> Int {
            var s = start
            while true {
                if up {
                    guard s > 0 else { return 0 }
                    s = text.lineRange(for: NSRange(location: s - 1, length: 0)).location
                } else {
                    s = NSMaxRange(text.lineRange(for: NSRange(location: s, length: 0)))
                    guard s < text.length else { return 0 }
                }
                if let l = own(s) { return l }
            }
        }
        return lineStarts.map { s in own(s) ?? min(nearest(from: s, up: true), nearest(from: s, up: false)) }
    }
}

/// The hanging indent of wrapped lines.
public enum HangingIndent {
    /// Where continuation lines of a paragraph start, in character widths: the width of its leading blanks plus `extra`.
    /// A tab advances to the next multiple of `tabWidth` (itself in character widths).
    public static func columns(_ paragraph: some StringProtocol, extra: Int, tabWidth: Double) -> Double {
        var x = 0.0
        for c in paragraph.utf16 {
            if c == 32 { x += 1 }
            else if c == 9, tabWidth > 0 { x = (floor(x / tabWidth + 1e-9) + 1) * tabWidth }
            else { break }
        }
        return x + Double(max(extra, 0))
    }
}

/// The other places in one file that name the same binding or label as the one at a position.
public enum Occurrences {
    /// Ranges of the other occurrences, in `text`, of the identifier or label at `offset`; empty on prose, keywords and
    /// names that resolve to nothing in this file.
    /// shortcut: indexes only this file, so names from wildcard imports and `module.name` fields are not marked; use the
    /// project index if that matters.
    public static func ranges(in text: String, file: RelPath, at offset: Int) -> [NSRange] {
        let labels = LabelIndex.build([(file, text)])
        if let hit = labels.hit(in: file, at: offset) {
            let all = (labels.definitions[hit.name] ?? []) + (labels.references[hit.name] ?? []) + (labels.bibKeys[hit.name] ?? [])
            return all.filter { $0.file == file && $0 != hit.site }.map(\.token).sorted { $0.location < $1.location }
        }
        let index = BindingIndex.build([(file, text)])
        guard let symbol = index.symbol(in: file, at: offset) else { return [] }
        let sites = index.sites(of: symbol).filter { $0.file == file }.map(\.range)
        let own = sites.first { $0.location <= offset && offset <= NSMaxRange($0) }
        return sites.filter { $0 != own }.sorted { $0.location < $1.location }
    }
}

extension Buffer {
    /// Makes every paragraph's `.paragraphStyle` give its continuation lines the hanging indent of `wrapIndent`: sets
    /// missing ones, corrects changed ones, clears unneeded ones, touches nothing else. Runs with `syncKerns` because
    /// painting resets attributes over the repainted range.
    func syncWrapIndent() {
        let text = storage.string as NSString
        let char = ("0" as NSString).size(withAttributes: [.font: Highlighter.baseFont]).width
        guard char > 0 else { return }
        let tab = Double(indentSettings.tabWidth), interval = CGFloat(indentSettings.tabWidth) * char   // same stops as the text view's default style
        var start = 0
        while start < text.length {
            let line = text.lineRange(for: NSRange(location: start, length: 0))
            start = NSMaxRange(line)
            let want = CGFloat(HangingIndent.columns(Indent.leadingBlanks(text, from: line.location, to: NSMaxRange(line)), extra: wrapIndent, tabWidth: tab)) * char
            var effective = NSRange()
            let have = storage.attribute(.paragraphStyle, at: line.location, longestEffectiveRange: &effective, in: line) as? NSParagraphStyle
            if want == 0 {
                if have != nil || effective != line { storage.removeAttribute(.paragraphStyle, range: line) }
            } else if have?.headIndent != want || have?.defaultTabInterval != interval || effective != line {
                let style = NSMutableParagraphStyle()
                style.headIndent = want
                style.tabStops = []
                style.defaultTabInterval = interval
                storage.addAttribute(.paragraphStyle, value: style, range: line)
            }
        }
    }
}
