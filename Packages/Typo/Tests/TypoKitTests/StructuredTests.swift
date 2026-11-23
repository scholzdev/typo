import Foundation
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite(.serialized) @MainActor struct StructuredTests {
    nonisolated static let toml = """
    # comment
    [package]
    name = "demo"   # trailing
    version = '0.1.0'
    keywords = ["a", 'b']
    a.b."c d" = 1.5e3
    ok = true
    when = 1979-05-27T07:32:00Z
    meta = { x = 1, y = "z" }
    [[bin.x]]
    text = \"\"\"
    multi # not a comment
    \"\"\"
    """

    nonisolated static let bib = """
    % note
    @string{me = "Me"}
    @comment{ignored {x}}
    @article{key2024,
      author = {Doe, {J}ane} # " and " # me,
      year = 2024,
      title = "A \\"quoted\\" {Title}",
    }
    """

    /// Tags covering `needle` entirely (first occurrence), as the set of tags of spans inside it.
    func tags(_ needle: String, _ text: String, _ spans: [SyntaxSpan]) -> [SyntaxTag] {
        let r = (text as NSString).range(of: needle)
        precondition(r.location != NSNotFound, needle)
        return spans.filter { NSIntersectionRange($0.range, r) == $0.range && $0.range.length > 0 }.map(\.tag)
    }

    @Test func tomlTokens() {
        let s = StructuredLang.toml.spans(Self.toml)
        let t = { tags($0, Self.toml, s) }
        #expect(t("# comment") == [.comment])
        #expect(t("[package]") == [.punctuation, .heading, .punctuation])
        #expect(t("name") == [.function])
        #expect(t("\"demo\"") == [.string])
        #expect(t("# trailing") == [.comment])
        #expect(t("'0.1.0'") == [.string])
        #expect(t("[\"a\", 'b']") == [.punctuation, .string, .punctuation, .string, .punctuation])
        #expect(t("a.b.\"c d\" = 1.5e3") == [.function, .punctuation, .function, .punctuation, .function, .operator, .number])
        #expect(t("true") == [.keyword])
        #expect(t("1979-05-27T07:32:00Z") == [.number])
        #expect(t("{ x = 1, y = \"z\" }") == [.punctuation, .function, .operator, .number, .punctuation, .function, .operator, .string, .punctuation])
        #expect(t("[[bin.x]]") == [.punctuation, .heading, .punctuation, .heading, .punctuation])
        #expect(t("\"\"\"\nmulti # not a comment\n\"\"\"") == [.string])
    }

    @Test func bibTokens() {
        let s = StructuredLang.bib.spans(Self.bib)
        let t = { tags($0, Self.bib, s) }
        #expect(t("% note") == [.comment])
        #expect(t("@string{me = \"Me\"}") == [.keyword, .punctuation, .function, .operator, .punctuation, .string, .punctuation, .punctuation])
        #expect(t("ignored {x}") == [.comment])
        #expect(t("@article") == [.keyword])
        #expect(t("key2024") == [.label])
        #expect(t("author") == [.function])
        #expect(t("{Doe, {J}ane}") == [.punctuation, .string, .punctuation])
        #expect(t("year = 2024") == [.function, .operator, .number])
        #expect(t("\"A \\\"quoted\\\" {Title}\"") == [.punctuation, .string, .punctuation])
    }

    @Test func numberUnitSplit() {
        func split(_ s: String) -> (String, String) {
            let u = Array(s.utf16), n = Highlighter.numberSplit(u)
            return (String(decoding: u[..<n], as: UTF16.self), String(decoding: u[n...], as: UTF16.self))
        }
        for (s, n, u) in [("2cm", "2", "cm"), ("12pt", "12", "pt"), ("1.5em", "1.5", "em"), ("1fr", "1", "fr"), ("30%", "30", "%"),
                          ("90deg", "90", "deg"), ("2rad", "2", "rad"), ("1e3", "1e3", ""), ("1e3em", "1e3", "em"), (".5cm", ".5", "cm"),
                          ("0xff", "0xff", ""), ("42", "42", "")] {
            #expect(split(s) == (n, u), "\(s)")
        }
    }

    static func color(_ s: NSTextStorage, _ needle: String) -> PlatformColor? {
        s.attribute(.foregroundColor, at: (s.string as NSString).range(of: needle).location, effectiveRange: nil) as? PlatformColor
    }

    @Test func todoMarkersAreBoldOrangeInTypstCommentsOnly() async throws {
        let text = "TODO text \"TODO\" // TODO: x\n/* FIXME y */"
        let (p, _) = try await TestEnv.project(files: ["main.typ": text, "typst.toml": "# TODO t\n"])
        let b = try await p.open(RelPath("main.typ")!)
        let ns = text as NSString
        func styled(_ s: NSTextStorage, _ r: NSRange) -> Bool {
            (s.attribute(.font, at: r.location, effectiveRange: nil) as? PlatformFont) == Highlighter.boldFont
                && (s.attribute(.foregroundColor, at: r.location, effectiveRange: nil) as? PlatformColor) == Highlighter.theme[.todo]?.color
        }
        #expect(!styled(b.storage, ns.range(of: "TODO")))
        #expect(!styled(b.storage, ns.range(of: "TODO", range: NSRange(location: 11, length: 8))))
        #expect(styled(b.storage, ns.range(of: "TODO", range: NSRange(location: 20, length: 10))) && styled(b.storage, ns.range(of: "FIXME")))
        #expect(!styled(b.storage, ns.range(of: ": x")))
        #expect(Highlighter.theme[.todo]?.bold == true)
        let t = try await p.open(RelPath("typst.toml")!)
        #expect(!styled(t.storage, NSRange(location: 2, length: 4)))
    }

    @Test func unitsAreColouredInTypstButNotInProse() async throws {
        let text = "Prose 1fr here.\n#let a = 2cm + 30%\n$ 3pt $\n"
        let (p, _) = try await TestEnv.project(files: ["main.typ": text])
        let b = try await p.open(RelPath("main.typ")!)
        let c = { Self.color(b.storage, $0) }
        #expect(c("cm") == Highlighter.theme[.unit]?.color)
        #expect(c("2") == Highlighter.theme[.number]?.color)
        #expect(c("%") == Highlighter.theme[.unit]?.color)
        #expect(c("1fr") == Highlighter.base[.foregroundColor] as? PlatformColor)
        #expect(c("fr") == Highlighter.base[.foregroundColor] as? PlatformColor)
    }

    /// Edit sequence on a structured file: after every step the storage colours equal a full repaint.
    @Test(arguments: [("typst.toml", Self.toml), ("refs.bib", Self.bib)])
    func incrementalEqualsFull(_ name: String, _ text: String) async throws {
        let (p, _) = try await TestEnv.project(files: [name: text, "main.typ": "x"])
        let b = try await p.open(RelPath(name)!)
        var step = 0
        func check() {
            step += 1
            let ref = NSTextStorage(string: b.storage.string)
            Highlighter.paint(ref, StructuredLang(path: name)!.spans(b.storage.string), SyntaxTests.whole(ref))
            #expect(SyntaxTests.colorRuns(b.storage) == SyntaxTests.colorRuns(ref), "\(name) step \(step)")
        }
        let ns = { b.storage.string as NSString }
        check()
        for (needle, insert) in [("demo", "\"\"\""), ("name", "'"), ("when", "["), ("version", "{"), ("key2024", "{"), ("author", "\""), ("year", "@"), ("ignored", "}")] {
            let at = ns().range(of: needle)
            guard at.location != NSNotFound else { continue }
            type(b, insert, at: at.location); check()
            b.undoManager.undo(); check()
        }
        replace(b, NSRange(location: 0, length: b.storage.length), with: ""); check()
        replace(b, NSRange(location: 0, length: 0), with: text); check()
        #expect(b.structured != nil)
    }

    @Test func otherPlainFilesStayPlain() async throws {
        let (p, _) = try await TestEnv.project(files: ["data.json": "{\"a\": 1}", "main.typ": "x"])
        let b = try await p.open(RelPath("data.json")!)
        #expect(b.structured == nil)
        #expect(SyntaxTests.colorRuns(b.storage).count == 1)
    }
}
