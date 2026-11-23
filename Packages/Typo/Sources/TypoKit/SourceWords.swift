import Foundation
import TypstEngine

/// Words the author wrote: the prose of the main file and of every file it includes, in document order, split at
/// headings. Text Typst generates (numbering, "Figure 1", resolved references, page numbers, bibliography) and
/// code, math, strings and raw do not count.
enum SourceWords {
    struct Section: Equatable { var title: String, level: Int, words: Int }

    static func count(main: RelPath, text: [RelPath: String]) -> [Section] {
        var sections = [Section(title: "", level: 0, words: 0)]
        var open: Set<RelPath> = []
        func walk(_ file: RelPath) {
            guard let t = text[file], open.insert(file).inserted else { return }
            defer { open.remove(file) }
            enum Event { case heading(Int, String), include(RelPath), words(Int) }
            let ns = t as NSString
            var events: [(at: Int, order: Int, event: Event)] = []
            // shortcut: headings and includes are found by line pattern, so one inside raw text or a string counts; upgrade to the syntax tree if that matters.
            for m in t.matches(of: /(?m)^[ \t]*(=+)[ \t]+([^\n]*)$/) {
                let title = String(m.2).replacing(/\s*<[^<>\s]+>\s*$/, with: "").trimmingCharacters(in: .whitespaces)
                events.append((NSRange(m.range, in: t).location, 0, .heading(m.1.count, title)))
            }
            for m in t.matches(of: /#include\s+"([^"\n]+)"/) {
                if let target = CellCompletion.resolve(String(m.1), from: file) { events.append((NSRange(m.range, in: t).location, 1, .include(target))) }
            }
            for r in SyntaxMirror(t).prose(in: NSRange(location: 0, length: ns.length)) {
                events.append((r.location, 2, .words(Bridge.words(in: ns.substring(with: r)))))
            }
            for e in events.sorted(by: { ($0.at, $0.order) < ($1.at, $1.order) }) {
                switch e.event {
                case .heading(let level, let title): sections.append(Section(title: title, level: level, words: 0))
                case .include(let target): walk(target)
                case .words(let n): sections[sections.count - 1].words += n
                }
            }
        }
        walk(main)
        return sections
    }
}
