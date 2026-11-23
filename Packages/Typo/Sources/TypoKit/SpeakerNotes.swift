import Foundation
import TypstEngine

/// A speaker note call in the source: Touying's `#speaker-note[..]` or Polylux's `#pdfpc.speaker-note(..)`.
public struct SpeakerNote: Equatable, Sendable {
    /// UTF-16 offset of the call's `#`.
    public let offset: Int
    public let text: String
}

public enum SpeakerNotes {
    private static let call = try! NSRegularExpression(pattern: #"#(?:[\w-]+\.)*speaker-note([\[(])"#)
    /// Zero-size text placed before each note, so the compiled document says which page a note is on.
    static let marker = "#place(box(width: 0pt, height: 0pt, clip: true)[x])"
    private static let markerCursor = (marker as NSString).range(of: "x]").location + 1

    /// Every note call in `text`, in source order. Calls in comments, strings and raw text don't count.
    @MainActor static func extract(_ text: String) -> [SpeakerNote] {
        let ns = text as NSString, syntax = SyntaxMirror(text)
        return call.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            let open = m.range(at: 1).location
            // `mode` reports the character before the position, so +2 asks about the name after `#`.
            guard syntax.mode(at: m.range.location + 2) == .code,
                  let (whole, targets) = syntax.args(at: open + 1, minTargets: 1), whole.location == open,
                  let first = targets.first else { return nil }
            let note = clean(ns.substring(with: first))
            return note.isEmpty ? nil : SpeakerNote(offset: m.range.location, text: note)
        }
    }

    /// The argument as the speaker reads it: a string unescaped, raw text without its fences, markup as written.
    static func clean(_ arg: String) -> String {
        var s = arg.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count >= 2, s.hasPrefix("\""), s.hasSuffix("\"") {
            var out = "", escaped = false
            for c in s.dropFirst().dropLast() {
                if escaped {
                    out.append(c == "n" ? "\n" : c == "t" ? "\t" : c)
                    escaped = false
                } else if c == "\\" { escaped = true } else { out.append(c) }
            }
            s = out
        } else if s.hasPrefix("`") {
            let fence = s.prefix { $0 == "`" }.count
            s = String(s.dropFirst(fence).dropLast(min(fence, s.reversed().prefix { $0 == "`" }.count)))
            if fence >= 3 { s = String(s.drop { $0 != "\n" && $0 != " " }) }   // the language tag
        }
        return s.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `text` with `marker` before each note, and the cursor inside each note's marker.
    static func marked(_ text: String, _ notes: [SpeakerNote]) -> (text: String, cursors: [Int]) {
        let out = NSMutableString(string: text), length = (marker as NSString).length
        for n in notes.reversed() { out.insert(marker, at: n.offset) }
        return (out as String, notes.indices.map { notes[$0].offset + $0 * length + markerCursor })
    }

    /// Notes by page: a note goes to every page its marker lands on (Touying repeats a slide per `#pause`).
    static func byPage(_ notes: [SpeakerNote], pages: [[Int]]) -> [Int: String] {
        var out: [Int: [String]] = [:]
        for (note, at) in zip(notes, pages) {
            for page in Set(at) { out[page, default: []].append(note.text) }
        }
        return out.mapValues { $0.joined(separator: "\n\n") }
    }
}

extension Project {
    /// Speaker notes of the main file by 0-based page. It compiles a marked copy on a world of its own, so it
    /// is slow for a long deck; empty when there are none or the copy's page count differs from the preview's.
    /// shortcut: only the main file is scanned, extend to included files if decks split slides across files.
    public func speakerNotes() async -> [Int: String] {
        let texts = openTexts
        guard let text = texts[main] ?? (try? String(contentsOf: root.appending(path: main.raw), encoding: .utf8)) else { return [:] }
        let notes = SpeakerNotes.extract(text)
        guard !notes.isEmpty, let world = WorldHandle(runtime: runtime, root: root, main: main, onDownload: { _ in }) else { return [:] }
        let (marked, cursors) = SpeakerNotes.marked(text, notes)
        let main = main, expected = preview.pages.count
        let pages: [[Int]]? = await withCheckedContinuation { c in
            DispatchQueue.global(qos: .userInitiated).async {
                for (p, t) in texts where p != main { world.setText(p, t) }
                world.setText(main, marked)
                guard world.compile().pageCount == expected else { return c.resume(returning: nil) }
                c.resume(returning: cursors.map { world.jumpFromCursor(main, cursor: $0).map(\.page) })
            }
        }
        return pages.map { SpeakerNotes.byPage(notes, pages: $0) } ?? [:]
    }
}
