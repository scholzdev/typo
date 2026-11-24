import Foundation
import TypstEngine

/// A note for the speaker, in the source as Typo's `#metadata("…") <note>`, Touying's `#speaker-note[..]`
/// or Polylux's `#pdfpc.speaker-note(..)`.
public struct PresenterNote: Equatable, Sendable {
    public enum Kind: Sendable { case typo, touying, polylux }

    public let path: RelPath
    /// The whole call, including the label of a Typo note.
    public let callRange: NSRange
    public let text: String
    public let kind: Kind
    /// 0-based pages the note lands on (Touying repeats a slide per `#pause`).
    public var pages: [Int]
}

public enum PresenterNotes {
    struct Found: Equatable {
        let range: NSRange
        let text: String
        let kind: PresenterNote.Kind
    }

    private static let speakerCall = try! NSRegularExpression(pattern: #"#(?:[\w-]+\.)*speaker-note([\[(])"#)
    private static let metadataCall = try! NSRegularExpression(pattern: #"#metadata([\[(])"#)
    private static let label = try! NSRegularExpression(pattern: #"[ \t]*\n?[ \t]*<note>"#)
    /// Zero-size text placed before each note, so the compiled document says which page a note is on.
    static let marker = "#place(box(width: 0pt, height: 0pt, clip: true)[x])"
    private static let markerCursor = (marker as NSString).range(of: "x]").location + 1

    /// Every note in `text`, in source order. Calls in comments, strings and raw text don't count, and
    /// `#metadata` counts only with `<note>` right after it.
    @MainActor static func extract(_ text: String) -> [Found] {
        let ns = text as NSString, syntax = SyntaxMirror(text), all = NSRange(location: 0, length: ns.length)
        /// The call's range up to its closing bracket and its first argument.
        func call(_ m: NSTextCheckingResult) -> (NSRange, String)? {
            let open = m.range(at: 1).location
            // `mode` reports the character before the position, so +2 asks about the name after `#`.
            guard syntax.mode(at: m.range.location + 2) == .code,
                  let (whole, targets) = syntax.args(at: open + 1, minTargets: 1), whole.location == open,
                  let first = targets.first else { return nil }
            return (NSRange(location: m.range.location, length: NSMaxRange(whole) - m.range.location), ns.substring(with: first))
        }
        var out: [Found] = []
        for m in speakerCall.matches(in: text, range: all) {
            guard let (range, arg) = call(m) else { continue }
            let note = clean(arg)
            if !note.isEmpty { out.append(Found(range: range, text: note, kind: ns.substring(with: m.range).contains("pdfpc.") ? .polylux : .touying)) }
        }
        for m in metadataCall.matches(in: text, range: all) {
            guard let (range, arg) = call(m) else { continue }
            let rest = NSRange(location: NSMaxRange(range), length: ns.length - NSMaxRange(range))
            guard let l = label.firstMatch(in: text, options: .anchored, range: rest) else { continue }
            out.append(Found(range: NSUnionRange(range, l.range), text: clean(arg), kind: .typo))
        }
        return out.sorted { $0.range.location < $1.range.location }
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

    /// How Typo writes a note: only `\` and `"` are escaped, newlines become `\n`, so any text survives a round trip.
    public static func written(_ text: String) -> String {
        let s = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r\n", with: "\\n").replacingOccurrences(of: "\n", with: "\\n")
        return "#metadata(\"\(s)\") <note>"
    }

    /// The text a card shows for a note call: the string a line written by `written` holds, exactly, or the content
    /// of a one-line `#metadata[…] <note>` as written (a card edit writes it back in the string form); nil otherwise.
    static func unwritten(_ call: String) -> String? {
        if call.hasPrefix("#metadata["), call.hasSuffix("] <note>"), !call.contains("\n") {
            return String(call.dropFirst("#metadata[".count).dropLast("] <note>".count))
        }
        let head = "#metadata(\"", tail = "\") <note>"
        guard call.hasPrefix(head), call.hasSuffix(tail), call.count >= head.count + tail.count else { return nil }
        var out = "", escaped = false
        for c in call.dropFirst(head.count).dropLast(tail.count) {
            if escaped {
                switch c {
                case "n": out.append("\n")
                case "\\", "\"": out.append(c)
                default: return nil
                }
                escaped = false
            } else if c == "\\" { escaped = true } else { out.append(c) }
        }
        return escaped || written(out) != call ? nil : out
    }

    /// A line the editor shows as a note card: only Typo's `#metadata("…") <note>` on it, besides spaces and tabs.
    public struct CardLine: Equatable, Sendable {
        /// The whole line, with its line break.
        public let line: NSRange
        public let call: NSRange
        public let text: String
    }

    /// A note the editor shows as a pill over its call: Typo's note sharing its line with other text.
    public struct InlineNote: Equatable, Sendable {
        public var call: NSRange
        public var lineStart: Int
        public let text: String
    }

    /// Card lines and inline notes of `text` from one parse, in source order. Only calls `unwritten` reads count, so a
    /// call split over lines stays code, and notes in comments, strings and raw text are neither.
    @MainActor public static func noteLines(in text: String) -> (cards: [CardLine], inline: [InlineNote]) {
        guard text.contains("<note>") else { return ([], []) }
        let ns = text as NSString
        var cards: [CardLine] = [], inline: [InlineNote] = []
        for n in extract(text) where n.kind == .typo {
            let call = ns.substring(with: n.range), line = ns.lineRange(for: n.range)
            guard let note = unwritten(call) else { continue }
            if ns.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines) == call {
                cards.append(CardLine(line: line, call: n.range, text: note))
            } else {
                inline.append(InlineNote(call: n.range, lineStart: line.location, text: note))
            }
        }
        return (cards, inline)
    }

    @MainActor public static func cardLines(in text: String) -> [CardLine] { noteLines(in: text).cards }
    @MainActor public static func inlineNotes(in text: String) -> [InlineNote] { noteLines(in: text).inline }

    /// `text` with `marker` before each note, and the cursor inside each note's marker.
    static func marked(_ text: String, _ notes: [Found]) -> (text: String, cursors: [Int]) {
        let out = NSMutableString(string: text), length = (marker as NSString).length
        for n in notes.reversed() { out.insert(marker, at: n.range.location) }
        return (out as String, notes.indices.map { notes[$0].range.location + $0 * length + markerCursor })
    }

    /// Notes by page: a note goes to every page its marker lands on.
    public static func byPage(_ notes: [PresenterNote]) -> [Int: [PresenterNote]] {
        var out: [Int: [PresenterNote]] = [:]
        for n in notes { for page in Set(n.pages) { out[page, default: []].append(n) } }
        return out
    }

    /// The notes' texts joined per page, for the presenter view; notes without text stay out.
    public static func texts(_ notes: [PresenterNote]) -> [Int: String] {
        byPage(notes).mapValues { $0.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n\n") }.filter { !$0.value.isEmpty }
    }

    /// `\n` + a new note after the line holding `offset`; the line's own break stays where it was, so a paragraph is not split.
    public static func insertion(of note: String, afterLineAt offset: Int, in text: String) -> Replacement {
        let ns = text as NSString
        let end = NSMaxRange(ns.lineRange(for: NSRange(location: min(offset, ns.length), length: 0)))
        let atBreak = end > 0 && end <= ns.length && ns.character(at: end - 1) == 0x0A
        return Replacement(range: NSRange(location: atBreak ? end - 1 : end, length: 0), text: "\n" + note)
    }

    /// Writes `text` over `note`'s call; empty text removes the call, and its line when nothing else is on it, else one
    /// space or tab next to it (after it, else before), so no double space is left.
    public static func replacement(for note: NSRange, in text: String, writing newText: String) -> Replacement {
        guard newText.isEmpty else { return Replacement(range: note, text: written(newText)) }
        let ns = text as NSString
        let line = ns.lineRange(for: note)
        let rest = ns.substring(with: line).replacingOccurrences(of: ns.substring(with: note), with: "")
        guard rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let blank = { (i: Int) in ns.character(at: i) == 0x20 || ns.character(at: i) == 0x09 }
            if NSMaxRange(note) < ns.length, blank(NSMaxRange(note)) { return Replacement(range: NSRange(location: note.location, length: note.length + 1), text: "") }
            if note.location > line.location, blank(note.location - 1) { return Replacement(range: NSRange(location: note.location - 1, length: note.length + 1), text: "") }
            return Replacement(range: note, text: "")
        }
        // Alone on its line: take the line break with it; on the last line, the break before it.
        if NSMaxRange(line) < ns.length || line.location == 0 { return Replacement(range: line, text: "") }
        return Replacement(range: NSRange(location: line.location - 1, length: line.length + 1), text: "")
    }

    /// The Typo note in `text` that `old` stood for, found again after edits: same call text at the same place, else the
    /// nearest one with the same note text.
    @MainActor static func locate(_ old: PresenterNote, in text: String) -> PresenterNotes.Found? {
        let found = extract(text).filter { $0.kind == old.kind && $0.text == old.text }
        return found.first { $0.range == old.callRange } ?? found.min { abs($0.range.location - old.callRange.location) < abs($1.range.location - old.callRange.location) }
    }
}

/// Asks a model: (system prompt, message) -> reply. The app wires it to the user's provider; tests pass a stub.
public typealias PresenterNoteDrafter = @Sendable (_ system: String, _ message: String) async throws -> String

extension PresenterNotes {
    public static let draftSystem = """
        You write speaker notes for one slide of a presentation whose source is written in Typst. Reply with the notes only: \
        two to five short sentences the speaker can read aloud, in plain text without markup, headings, bullet points or \
        quotation marks. Write in the language of the slide. Do not repeat the slide word for word; say what the speaker adds.
        """

    /// The slide's source with its neighbours for context, and the note already there, if any.
    public static func draftMessage(slide: String, number: Int, total: Int, previous: String?, next: String?, existing: String?) -> String {
        var out = "Write the speaker notes for slide \(number) of \(total).\n\nSlide \(number), as Typst source:\n```typst\n\(slide)\n```"
        if let previous, !previous.isEmpty { out += "\n\nThe previous slide, for context:\n```typst\n\(previous)\n```" }
        if let next, !next.isEmpty { out += "\n\nThe next slide, for context:\n```typst\n\(next)\n```" }
        if let existing, !existing.isEmpty { out += "\n\nThe current notes, to improve on:\n\(existing)" }
        return out
    }

    /// The reply as note text: surrounding code fences and quotation marks removed.
    public static func draftText(fromReply reply: String) -> String {
        var s = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            s = String(s.drop { $0 != "\n" }).trimmingCharacters(in: .whitespacesAndNewlines)
            if s.hasSuffix("```") { s = String(s.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        if s.count >= 2, s.hasPrefix("\""), s.hasSuffix("\""), !s.dropFirst().dropLast().contains("\"") { s = String(s.dropFirst().dropLast()) }
        return s
    }
}

extension Project {
    /// Every `.typ` file with its text: the open buffer's, else the disk's.
    private func sourceTexts() -> [RelPath: String] {
        let open = openTexts
        var out: [RelPath: String] = [:]
        for f in allFiles where f.raw.hasSuffix(".typ") {
            if let t = open[f] ?? (try? String(contentsOf: url(for: f), encoding: .utf8)) { out[f] = t }
        }
        return out
    }

    /// Sets `preview.automaticNotes`: the strip shows by itself in a project with presenter notes or a slide package.
    public func detectPresenterContent() {
        preview.automaticNotes = sourceTexts().values.contains {
            $0.contains("@preview/touying") || $0.contains("@preview/polylux") || $0.contains("speaker-note")
                || ($0.contains("<note>") && !PresenterNotes.extract($0).isEmpty)
        }
    }

    /// The notes of the whole project with the pages they are on; a note on no page is dropped. It compiles a marked copy
    /// on a world of its own, so it is slow for a long deck; empty when the copy's page count differs from the preview's.
    public func presenterNotes() async -> [PresenterNote] {
        let texts = sourceTexts()
        let found = texts.filter { $0.value.contains("metadata") || $0.value.contains("speaker-note") }
            .mapValues { PresenterNotes.extract($0) }.filter { !$0.value.isEmpty }
        guard !found.isEmpty, let world = WorldHandle(runtime: runtime, root: root, main: main, onDownload: { _ in }) else { return [] }
        var overlays = texts, cursors: [RelPath: [Int]] = [:]
        for (path, notes) in found {
            let m = PresenterNotes.marked(texts[path]!, notes)
            overlays[path] = m.text
            cursors[path] = m.cursors
        }
        let expected = preview.pages.count, overlay = overlays, cursor = cursors
        let pages: [RelPath: [[Int]]]? = await withCheckedContinuation { c in
            DispatchQueue.global(qos: .userInitiated).async {
                for (p, t) in overlay { world.setText(p, t) }
                guard world.compile().pageCount == expected else { return c.resume(returning: nil) }
                c.resume(returning: cursor.reduce(into: [:]) { out, e in
                    out[e.key] = e.value.map { world.jumpFromCursor(e.key, cursor: $0).map(\.page) }
                })
            }
        }
        guard let pages else { return [] }
        return found.sorted { $0.key.raw < $1.key.raw }.flatMap { path, notes in
            zip(notes, pages[path] ?? []).compactMap { n, at in
                at.isEmpty ? nil : PresenterNote(path: path, callRange: n.range, text: n.text, kind: n.kind, pages: Array(Set(at)).sorted())
            }
        }
    }

    /// Source positions shown on `pages`, per page and in order from the bottom of the page upward, found by looking up what
    /// is at points of the page. `limit` stops a page's sweep after that many hits.
    private func pageHits(_ pages: [Int], limit: Int, texts: [RelPath: String]) async -> [Int: [(RelPath, Int)]] {
        guard let world = WorldHandle(runtime: runtime, root: root, main: main, onDownload: { _ in }) else { return [:] }
        let expected = preview.pages.count
        return await withCheckedContinuation { c in
            DispatchQueue.global(qos: .userInitiated).async {
                for (p, t) in texts { world.setText(p, t) }
                let snapshot = world.compile()
                guard snapshot.pageCount == expected else { return c.resume(returning: [:]) }
                var out: [Int: [(RelPath, Int)]] = [:]
                for page in pages where snapshot.pages.indices.contains(page) {
                    let size = snapshot.pages[page].size
                    var hits: [(RelPath, Int)] = []
                    for y in stride(from: size.height - 1, to: 0, by: -6) where hits.count < limit {
                        for fx in [0.5, 0.2, 0.35, 0.65, 0.8, 0.1] {
                            guard case .file(let path, let offset)? = world.jumpFromClick(shown: snapshot, page: page, point: CGPoint(x: size.width * fx, y: y)) else { continue }
                            hits.append((path, offset))
                        }
                    }
                    out[page] = hits
                }
                c.resume(returning: out)
            }
        }
    }

    /// Where a note for 0-based `page` goes: the file and the offset of the end of a markup line shown on that page, found
    /// by looking up from the bottom of the page for text that maps back to a source line. Nil when the page shows no
    /// project text.
    func presenterNotePosition(page: Int) async -> (path: RelPath, offset: Int, text: String)? {
        let texts = sourceTexts()
        for (path, offset) in await pageHits([page], limit: 24, texts: texts)[page] ?? [] {
            guard let text = texts[path] else { continue }
            let ns = text as NSString
            let lineEnd = NSMaxRange(ns.lineRange(for: NSRange(location: min(offset, ns.length), length: 0)))
            let end = lineEnd > 0 && lineEnd <= ns.length && ns.character(at: lineEnd - 1) == 0x0A ? lineEnd - 1 : lineEnd
            if SyntaxMirror(text).mode(at: end) == .markup { return (path, end, text) }
        }
        return nil
    }

    /// The source lines that make up `page`, for a model to read: from the first to the last line the page maps back to
    /// in the file most of it comes from.
    func presenterPageSources(_ pages: [Int]) async -> [Int: String] {
        let texts = sourceTexts()
        var out: [Int: String] = [:]
        for (page, hits) in await pageHits(pages, limit: .max, texts: texts) {
            let byFile = Dictionary(grouping: hits, by: \.0)
            guard let (path, inFile) = byFile.max(by: { $0.value.count < $1.value.count }), let text = texts[path] else { continue }
            let ns = text as NSString, offsets = inFile.map { min($0.1, ns.length) }
            let first = ns.lineRange(for: NSRange(location: offsets.min()!, length: 0)), last = ns.lineRange(for: NSRange(location: offsets.max()!, length: 0))
            out[page] = ns.substring(with: NSUnionRange(first, last)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return out
    }

    /// A draft of the note for `page`, asked of `draft` (system prompt, message) with the neighbouring slides as context.
    /// Nil when the page shows no project text.
    public func draftPresenterNote(page: Int, using draft: PresenterNoteDrafter) async throws -> String? {
        let sources = await presenterPageSources([page - 1, page, page + 1].filter { $0 >= 0 && $0 < preview.pages.count })
        guard let slide = sources[page], !slide.isEmpty else { return nil }
        let existing = await presenterNotes().filter { $0.pages.contains(page) }.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n\n")
        let message = PresenterNotes.draftMessage(slide: slide, number: page + 1, total: preview.pages.count,
                                                  previous: sources[page - 1], next: sources[page + 1], existing: existing)
        return PresenterNotes.draftText(fromReply: try await draft(PresenterNotes.draftSystem, message))
    }

    /// Sets the note of `page`: replaces `note` (a Typo note) with `text`, removing it when `text` is empty, or adds a new
    /// note on the page. One undo step "Edit Presenter Note" in the file's buffer. False when nothing was written, e.g.
    /// the note has moved or the file changed meanwhile.
    @discardableResult public func setPresenterNote(_ text: String, replacing note: PresenterNote?, onPage page: Int, actionName name: String) async -> Bool {
        if let note {
            guard note.kind == .typo, let buffer = try? await open(note.path),
                  let at = PresenterNotes.locate(note, in: buffer.storage.string) else { return false }
            buffer.apply([PresenterNotes.replacement(for: at.range, in: buffer.storage.string, writing: text)], actionName: name)
            return true
        }
        guard !text.isEmpty, let (path, offset, before) = await presenterNotePosition(page: page), let buffer = try? await open(path),
              buffer.storage.string == before else { return false }
        buffer.apply([PresenterNotes.insertion(of: PresenterNotes.written(text), afterLineAt: offset, in: before)], actionName: name)
        return true
    }

    /// Opens the note's file and selects its call, found again if the text has shifted.
    public func reveal(_ note: PresenterNote) {
        Task {
            let range = (try? await open(note.path)).flatMap { PresenterNotes.locate(note, in: $0.storage.string)?.range } ?? note.callRange
            show(note.path, range: range, flash: true)
        }
    }
}
