import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite struct AccessibilityTests {
    static let ready = "#set document(title: [T])\n#set text(lang: \"en\")\n"
    static func f(_ s: String) -> RelPath { RelPath(s)! }

    /// Hints as "file:token message".
    static func hints(_ files: [String: String], main: String = "main.typ") -> [String] {
        let sources = files.keys.sorted().map { (file: f($0), text: files[$0]!) }
        return Accessibility.hints(sources: sources, main: f(main)).map { d in
            guard case .project(let loc) = d.origin else { return d.message }
            #expect(d.severity == .hint)
            return "\(loc.file.raw):\((files[loc.file.raw]! as NSString).substring(with: loc.range)) \(d.message)"
        }
    }

    /// The text after applying the one fix of the first hint with `rule` in `text`, and the selected text.
    static func fixed(_ text: String, _ rule: Accessibility.Rule, language: String = "de") -> (text: String, selected: String)? {
        let sources = [(file: f("main.typ"), text: text)]
        guard let d = Accessibility.hints(sources: sources, main: f("main.typ")).first(where: { Accessibility.rule(of: $0.message) == rule }),
              case .project(let loc) = d.origin,
              let fix = Accessibility.fixes(rule, file: loc.file, range: loc.range, text: text, language: language).first,
              let edit = fix.edits[loc.file]?.first else { return nil }
        let out = (text as NSString).replacingCharacters(in: edit.range, with: edit.text)
        return (out, fix.selection.map { (out as NSString).substring(with: $0) } ?? "")
    }

    @Test func cleanDocumentHasNoHints() {
        #expect(Self.hints(["main.typ": Self.ready + "= A\n== B\n#image(\"a.png\", alt: \"x\")\n#table(columns: 2, table.header[a][b], [c], [d])\n"]) == [])
    }

    @Test func imageWithoutAlt() {
        let hs = Self.hints(["main.typ": Self.ready + "#image(\"a.png\")\n#figure(image(\"b.png\"), caption: [c])\n#image(\"c.png\", alt: \"c\")\n#figure(image(\"d.png\"), alt: \"d\")\n"])
        #expect(hs == ["main.typ:image Image has no alternative text (PDF/UA)", "main.typ:image Image has no alternative text (PDF/UA)"])
    }

    @Test func imageFix() throws {
        let a = try #require(Self.fixed(Self.ready + "#image(\"a.png\", width: 5cm)\n", .imageAlt))
        #expect(a.text == Self.ready + "#image(\"a.png\", width: 5cm, alt: \"\")\n")
        #expect(a.selected == "")
        let r = try #require(Self.fixed("#figure(image(\"a.png\"))", .imageAlt))
        #expect(r.text == "#figure(image(\"a.png\", alt: \"\"))")
    }

    @Test func headingLevelsThatSkip() throws {
        #expect(Self.hints(["main.typ": Self.ready + "= A\n=== B\n== C\n==== D\n= E\n=== F\n```\n=== not a heading\n```\n"])
                == ["main.typ:=== Heading level jumps from 1 to 3 (PDF/UA)", "main.typ:==== Heading level jumps from 2 to 4 (PDF/UA)", "main.typ:=== Heading level jumps from 1 to 3 (PDF/UA)"])
        #expect(Self.hints(["main.typ": Self.ready + "= A\n", "ch.typ": "=== Deep start\n"]) == [])
        let fixed = try #require(Self.fixed(Self.ready + "= A\n=== B\n", .headingLevel))
        #expect(fixed.text == Self.ready + "= A\n== B\n")
    }

    @Test func tableWithoutHeader() throws {
        #expect(Self.hints(["main.typ": Self.ready + "#table(columns: 2, [a], [b], [c], [d])\n#table(columns: 1, table.header([h]), [c])\n#table(columns: 2, ..cells)\n"])
                == ["main.typ:table Table has no header row (PDF/UA)"])
        let a = try #require(Self.fixed("#table(columns: 2, [a], [b], [c], [d])", .tableHeader))
        #expect(a.text == "#table(columns: 2, table.header([a], [b]), [c], [d])")
        let b = try #require(Self.fixed("#table(\n  columns: (1fr, auto, auto),\n  [a], [b], [c],\n  [d], [e], [f],\n)", .tableHeader))
        #expect(b.text == "#table(\n  columns: (1fr, auto, auto),\n  table.header([a], [b], [c]),\n  [d], [e], [f],\n)")
        #expect(Self.fixed("#table(columns: (1fr,) * 2, [a], [b])", .tableHeader) == nil)
        #expect(Self.fixed("#table(columns: 2, [a], table.cell(colspan: 1)[b])", .tableHeader) == nil)
    }

    @Test func documentTitle() throws {
        #expect(Self.hints(["main.typ": "#set text(lang: \"en\")\nHello\n"]) == ["main.typ:#set text(lang: \"en\") Document has no title (PDF/UA)"])
        #expect(Self.hints(["main.typ": "#set text(lang: \"en\")\n#include \"t.typ\"\n", "t.typ": "#set document(title: [X])"]) == [])
        let a = try #require(Self.fixed("#set page(\n  margin: 1cm,\n)\n#set text(lang: \"en\")\n// c\nHello\n", .documentTitle))
        #expect(a.text == "#set page(\n  margin: 1cm,\n)\n#set text(lang: \"en\")\n#set document(title: [])\n// c\nHello\n")
        #expect(a.selected == "")
        #expect(Self.fixed("#set text(lang: \"en\")\nHello", .documentTitle)?.text == "#set text(lang: \"en\")\n#set document(title: [])\nHello")
        #expect(Self.fixed("#set text(lang: \"en\")\n#set document(author: \"A\")\n", .documentTitle)?.text == "#set text(lang: \"en\")\n#set document(author: \"A\", title: [])\n")
    }

    @Test func textLanguage() throws {
        #expect(Self.hints(["main.typ": "#set document(title: [T])\nHello\n"]) == ["main.typ:#set document(title: [T]) Text language is not set (PDF/UA)"])
        #expect(Self.hints(["main.typ": "#set document(title: [T])\n#include \"t.typ\"\n", "t.typ": "#set text(lang: \"de\")"]) == [])
        let a = try #require(Self.fixed("#set document(title: [T])", .textLanguage, language: "fr"))
        #expect(a.text == "#set document(title: [T])\n#set text(lang: \"fr\")\n")
        #expect(a.selected == "fr")
        #expect(Self.fixed("Hello", .textLanguage)?.text == "#set text(lang: \"de\")\nHello")
    }

    @Test func templateSilencesTitleAndLanguage() {
        #expect(Self.hints(["main.typ": "#import \"t.typ\": paper\n#show: paper\nHello\n", "t.typ": "#let paper(body) = body"]) == [])
    }

    @Test func onlyFilesReachableFromMainAreChecked() {
        #expect(Self.hints(["main.typ": Self.ready + "Hi", "other.typ": "#image(\"a.png\")"]) == [])
        #expect(Self.hints(["main.typ": Self.ready + "#include \"ch.typ\"", "ch.typ": "#image(\"a.png\")"]) == ["ch.typ:image Image has no alternative text (PDF/UA)"])
    }

    @Test func messagesMapToRules() {
        #expect(QuickFixes.kind(of: "Image has no alternative text (PDF/UA)") == .accessibility(.imageAlt))
        #expect(QuickFixes.kind(of: "Heading level jumps from 1 to 3 (PDF/UA)") == .accessibility(.headingLevel))
        #expect(QuickFixes.kind(of: "Image has no alternative text") == nil)
    }
}

@Suite struct ProjectAccessibilityTests {
    @Test @MainActor func hintsOnlyWhileChecksAreOn() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "#image(\"a.png\")\n"])
        _ = await p.settle()
        p.lintEnabled = false
        await p.runLint()
        #expect(p.lintHints.isEmpty)
        p.accessibilityChecks = true
        await p.runLint()
        #expect(p.lintHints.contains { $0.message == "Image has no alternative text (PDF/UA)" })
        let main = LintTests.f("main.typ")
        let d = try #require(p.lintHints(in: main).first { $0.message.hasPrefix("Image") })
        #expect(await p.quickFixes(for: d).map(\.title) == ["Add `alt: \"\"`"])
        p.accessibilityChecks = false
        #expect(p.lintHints.isEmpty)
    }
}
