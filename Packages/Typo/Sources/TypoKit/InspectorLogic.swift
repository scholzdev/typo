import Foundation
import TypstEngine

/// A call `name(...)` in Typst source with its arguments, for the inspector. Offsets are UTF-16.
public struct TypstCall: Equatable, Sendable {
    public struct Arg: Equatable, Sendable {
        public let name: String?
        /// The whole argument, trimmed.
        public let range: NSRange
        /// After `name:`, trimmed; the whole argument when positional.
        public let value: NSRange
    }
    public let name: String
    /// From the name through the closing parenthesis.
    public let range: NSRange
    public let args: [Arg]

    public var close: Int { NSMaxRange(range) - 1 }
    public func arg(_ name: String) -> Arg? { args.first { $0.name == name } }
}

public enum TypstCalls {
    /// Every call of one of `names` (`#figure(`, `table(`, ...), outer before inner.
    public static func calls(named names: Set<String>, in text: String) -> [TypstCall] {
        let ns = text as NSString
        var out: [TypstCall] = []
        for t in TypstSyntax.tokens(in: text) where t.tag == .function && NSMaxRange(t.range) < ns.length && ns.character(at: NSMaxRange(t.range)) == 0x28 {
            let name = ns.substring(with: t.range)
            if names.contains(name), let call = parse(name, nameAt: t.range.location, open: NSMaxRange(t.range), in: ns) { out.append(call) }
        }
        return out
    }

    /// The innermost call of `names` whose parentheses hold `offset`.
    public static func innermost(named names: Set<String>, in text: String, at offset: Int) -> TypstCall? {
        calls(named: names, in: text).filter { $0.range.location <= offset && offset <= $0.close }.last
    }

    /// Matches the parenthesis at `open`, splitting its top-level arguments on commas.
    /// shortcut: a `"` inside a content block counts as plain text, `#f("]")` inside one is not understood.
    private static func parse(_ name: String, nameAt: Int, open: Int, in ns: NSString) -> TypstCall? {
        var stack: [unichar] = [0x28]
        var starts = [open + 1]
        var cuts: [Int] = []
        var i = open + 1
        func skipString() { i += 1; while i < ns.length, ns.character(at: i) != 0x22 { i += ns.character(at: i) == 0x5C ? 2 : 1 } }
        while i < ns.length {
            let c = ns.character(at: i)
            let inContent = stack.last == 0x5B
            switch c {
            case 0x5C: i += 1
            case 0x2F where i + 1 < ns.length && ns.character(at: i + 1) == 0x2F:
                while i < ns.length, ns.character(at: i) != 0x0A { i += 1 }
            case 0x2F where i + 1 < ns.length && ns.character(at: i + 1) == 0x2A:
                let end = ns.range(of: "*/", range: NSRange(location: i + 2, length: ns.length - i - 2))
                i = end.location == NSNotFound ? ns.length : NSMaxRange(end) - 1
            case 0x22 where !inContent: skipString()
            case 0x5B: stack.append(c)
            case 0x28 where !inContent, 0x7B where !inContent: stack.append(c)
            case 0x5D where inContent, 0x29 where stack.last == 0x28, 0x7D where stack.last == 0x7B:
                stack.removeLast()
                if stack.isEmpty {
                    cuts.append(i)
                    var args: [TypstCall.Arg] = []
                    for (s, e) in zip(starts, cuts) { if let a = arg(NSRange(location: s, length: e - s), in: ns) { args.append(a) } }
                    return TypstCall(name: name, range: NSRange(location: nameAt, length: i + 1 - nameAt), args: args)
                }
            case 0x2C where stack.count == 1: cuts.append(i); starts.append(i + 1)
            default: break
            }
            i += 1
        }
        return nil
    }

    private static func arg(_ r: NSRange, in ns: NSString) -> TypstCall.Arg? {
        let t = trimmed(r, in: ns)
        guard t.length > 0 else { return nil }
        let text = ns.substring(with: t)
        if let m = text.prefixMatch(of: /([A-Za-z_][\w-]*)[ \t\r\n]*:(?!:)[ \t\r\n]*/) {
            let skip = (String(text[..<m.output.0.endIndex]) as NSString).length
            return TypstCall.Arg(name: String(m.output.1), range: t, value: trimmed(NSRange(location: t.location + skip, length: t.length - skip), in: ns))
        }
        return TypstCall.Arg(name: nil, range: t, value: t)
    }

    private static func trimmed(_ r: NSRange, in ns: NSString) -> NSRange {
        var a = r.location, b = NSMaxRange(r)
        let space: (Int) -> Bool = { [0x20, 0x09, 0x0A, 0x0D].contains(ns.character(at: $0)) }
        while a < b, space(a) { a += 1 }
        while b > a, space(b - 1) { b -= 1 }
        return NSRange(location: a, length: b - a)
    }
}

/// The `figure(...)` around the caret, its readable fields and the text edits that change them.
public struct FigureInfo: Equatable, Sendable {
    public enum Field: String, CaseIterable, Sendable { case caption, label, placement, kind, alt }

    public let call: TypstCall
    /// `<name>` right behind the call (and its trailing content blocks); nil when there is none.
    public let labelRange: NSRange?
    let text: String

    public static func at(_ offset: Int, in text: String) -> FigureInfo? {
        TypstCalls.innermost(named: ["figure"], in: text, at: offset).map { FigureInfo($0, text) }
    }

    init(_ call: TypstCall, _ text: String) {
        self.call = call
        self.text = text
        labelRange = Self.label(after: call, in: text as NSString)
    }

    /// The figure's `image(...)`; `alt:` belongs to it.
    private var image: TypstCall? { TypstCalls.calls(named: ["image"], in: text).first { NSLocationInRange($0.range.location, call.range) } }

    /// What a field's text box shows: a caption's content or string without its delimiters, an argument's source as written, the label's name.
    public func value(_ field: Field) -> String {
        let ns = text as NSString
        if field == .label { return labelRange.map { ns.substring(with: NSRange(location: $0.location + 1, length: $0.length - 2)) } ?? "" }
        guard let a = (field == .alt ? image : call)?.arg(field.rawValue) else { return "" }
        let v = ns.substring(with: a.value)
        if field == .alt || field == .caption, v.count >= 2, (v.hasPrefix("[") && v.hasSuffix("]")) || (v.hasPrefix("\"") && v.hasSuffix("\"")) {
            let inner = String(v.dropFirst().dropLast())
            return v.hasPrefix("\"") ? inner.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\") : inner
        }
        return v
    }

    /// The edit that sets `field` to `value` (empty removes it); nil when `value` cannot be written (an invalid label name).
    public func edit(_ field: Field, to value: String) -> Replacement? {
        if field == .label { return labelEdit(value) }
        guard let call = field == .alt ? image : call else { return nil }
        let new = field == .caption ? captionSource(value) : field == .alt ? Self.quoted(value) : value
        guard let a = call.arg(field.rawValue) else {
            guard !value.isEmpty else { return nil }
            guard let last = call.args.last else { return Replacement(range: NSRange(location: call.close, length: 0), text: "\(field.rawValue): \(new)") }
            return Replacement(range: NSRange(location: NSMaxRange(last.range), length: 0), text: ", \(field.rawValue): \(new)")
        }
        if !value.isEmpty { return Replacement(range: a.value, text: new) }
        // Remove the argument with the comma that separates it from its neighbour.
        guard let i = call.args.firstIndex(of: a) else { return nil }
        if i > 0 { let p = call.args[i - 1]; return Replacement(range: NSRange(location: NSMaxRange(p.range), length: NSMaxRange(a.range) - NSMaxRange(p.range)), text: "") }
        let end = i + 1 < call.args.count ? call.args[i + 1].range.location : NSMaxRange(a.range)
        return Replacement(range: NSRange(location: a.range.location, length: end - a.range.location), text: "")
    }

    private static func quoted(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }

    /// A caption keeps the form it has: a string stays a string, anything else is a content block (a string when its brackets do not balance).
    private func captionSource(_ s: String) -> String {
        var depth = 0, balanced = true
        for c in s { if c == "[" { depth += 1 } else if c == "]" { depth -= 1; if depth < 0 { balanced = false } } }
        let wasString = call.arg("caption").map { (text as NSString).substring(with: $0.value).hasPrefix("\"") } ?? false
        guard wasString || !balanced || depth != 0 else { return "[\(s)]" }
        return "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private func labelEdit(_ name: String) -> Replacement? {
        if name.isEmpty { return labelRange.map { Replacement(range: NSRange(location: $0.location - 1, length: $0.length + 1), text: "") } }
        guard LabelIndex.isValidName(name) else { return nil }
        if let r = labelRange { return Replacement(range: r, text: "<\(name)>") }
        return Replacement(range: NSRange(location: Self.endWithBlocks(of: call, in: text as NSString), length: 0), text: " <\(name)>")
    }

    /// The end of the call and the content blocks that trail it (`figure(...)[body]`).
    private static func endWithBlocks(of call: TypstCall, in ns: NSString) -> Int {
        var end = NSMaxRange(call.range)
        while end < ns.length, ns.character(at: end) == 0x5B {
            var depth = 0, i = end
            while i < ns.length { let c = ns.character(at: i); if c == 0x5B { depth += 1 } else if c == 0x5D { depth -= 1; if depth == 0 { break } }; i += 1 }
            guard i < ns.length else { break }
            end = i + 1
        }
        return end
    }

    private static func label(after call: TypstCall, in ns: NSString) -> NSRange? {
        var i = endWithBlocks(of: call, in: ns)
        while i < ns.length, [0x20, 0x09].contains(ns.character(at: i)) { i += 1 }
        guard i < ns.length, ns.character(at: i) == 0x3C else { return nil }
        let m = ns.range(of: ">", range: NSRange(location: i, length: ns.length - i))
        guard m.location != NSNotFound, m.location > i + 1 else { return nil }
        let name = ns.substring(with: NSRange(location: i + 1, length: m.location - i - 1))
        return LabelIndex.isValidName(name) ? NSRange(location: i, length: m.location + 1 - i) : nil
    }
}

/// `@preview/name:1.2.3` as imported by a project.
public struct PackageUse: Equatable, Hashable, Sendable {
    public let namespace: String
    public let name: String
    public let version: String
    public var spec: String { "@\(namespace)/\(name):\(version)" }
    public init(namespace: String, name: String, version: String) { self.namespace = namespace; self.name = name; self.version = version }
}

public enum InspectorScan {
    /// Packages imported or included by a source, in order of first use.
    public static func packages(in text: String) -> [PackageUse] {
        var seen = Set<PackageUse>(), out: [PackageUse] = []
        for m in text.matches(of: /(?:import|include)[ \t]+"@([\w-]+)\/([\w-]+):([\w.+-]+)"/) {
            let p = PackageUse(namespace: String(m.output.1), name: String(m.output.2), version: String(m.output.3))
            if seen.insert(p).inserted { out.append(p) }
        }
        return out
    }

    /// Font names given to `text(font: ...)` / `#set text(font: ...)`, as a string or an array of strings.
    public static func fonts(in text: String) -> [String] {
        let ns = text as NSString
        var seen = Set<String>(), out: [String] = []
        for call in TypstCalls.calls(named: ["text"], in: text) {
            guard let v = call.arg("font")?.value else { continue }
            for m in ns.substring(with: v).matches(of: /"((?:[^"\\]|\\.)*)"/) {
                let name = String(m.output.1)
                if seen.insert(name).inserted { out.append(name) }
            }
        }
        return out
    }

    /// Project files named by `#include "x.typ"` / `#import "x.typ"` in `text`, resolved from `file`'s folder (`/x` from the root).
    public static func includedFiles(in text: String, from file: RelPath) -> [(path: RelPath, offset: Int)] {
        let base = file.parent?.raw.split(separator: "/").map(String.init) ?? []
        var out: [(RelPath, Int)] = []
        for m in text.matches(of: /(?:include|import)[ \t]+"([^"\n]+)"/) {
            let raw = String(m.output.1)
            guard !raw.hasPrefix("@") else { continue }
            var parts = raw.hasPrefix("/") ? [] : base
            for p in raw.split(separator: "/") {
                if p == ".." { guard !parts.isEmpty else { parts = ["\u{0}"]; break }; parts.removeLast() } else if p != "." { parts.append(String(p)) }
            }
            if let r = RelPath(parts.joined(separator: "/")) { out.append((r, text.utf16.distance(from: text.utf16.startIndex, to: m.range.lowerBound))) }
        }
        return out
    }

    /// Bibliography keys nothing cites, sorted.
    public static func uncited(keys: some Collection<String>, referenced: Set<String>) -> [String] {
        Set(keys).subtracting(referenced).sorted()
    }

    public static let wordsPerMinute = 230
    /// Whole minutes to read `words`; at least one for any text.
    public static func readingMinutes(words: Int) -> Int { words <= 0 ? 0 : max(1, (words + wordsPerMinute / 2) / wordsPerMinute) }
}

/// Facts about the whole document that no single compile result holds.
public struct DocumentFacts: Equatable, Sendable {
    public var characters = 0
    public var language: TextLanguage?
    public var packages: [PackageUse] = []
    public var fonts: [String] = []
    public var bibEntries = 0
    public var uncited: [String] = []
    public init(characters: Int = 0, language: TextLanguage? = nil, packages: [PackageUse] = [], fonts: [String] = [], bibEntries: Int = 0, uncited: [String] = []) {
        self.characters = characters; self.language = language; self.packages = packages; self.fonts = fonts; self.bibEntries = bibEntries; self.uncited = uncited
    }
}

public struct IncludeSite: Equatable, Hashable, Sendable {
    public let file: RelPath
    public let offset: Int
    public init(file: RelPath, offset: Int) { self.file = file; self.offset = offset }
}

extension Project {
    /// Characters, language, packages, fonts and bibliography use over the project's current text (open buffers win over disk).
    public func documentFacts() async -> DocumentFacts {
        await Self.facts(textSources { FileKind.isTypst($0) || BibliographyFile.isBibliography($0) }, main: main)
    }

    @concurrent private static func facts(_ sources: [SearchSource], main: RelPath) async -> DocumentFacts {
        let loaded = sources.compactMap(\.loaded)
        var f = DocumentFacts()
        var packages: [PackageUse] = [], fonts: [String] = []
        for (file, text) in loaded where FileKind.isTypst(file.raw) {
            f.characters += text.count
            packages += InspectorScan.packages(in: text)
            fonts += InspectorScan.fonts(in: text)
            if file == main { f.language = TextLanguage.documentDefault(in: text) }
        }
        f.packages = packages.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        f.fonts = fonts.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        let labels = LabelIndex.build(loaded)
        f.bibEntries = labels.bibKeys.count
        f.uncited = InspectorScan.uncited(keys: labels.bibKeys.keys, referenced: Set(labels.references.keys))
        return f
    }

    /// The places in other files that `#include` or `#import` `file`.
    public func includers(of file: RelPath) async -> [IncludeSite] {
        await Self.includers(of: file, textSources { FileKind.isTypst($0) })
    }

    @concurrent private static func includers(of file: RelPath, _ sources: [SearchSource]) async -> [IncludeSite] {
        sources.compactMap(\.loaded).flatMap { from, text in
            from == file ? [] : InspectorScan.includedFiles(in: text, from: from).filter { $0.path == file }.map { IncludeSite(file: from, offset: $0.offset) }
        }
    }
}

extension Buffer {
    /// Encoding and line ending the file had on disk (its text here is always LF).
    public var diskFormat: FileFormat { fileFormat }
}

