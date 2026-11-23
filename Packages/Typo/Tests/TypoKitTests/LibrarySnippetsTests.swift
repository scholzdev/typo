import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit

@MainActor struct LibrarySnippetsTests {
    private func snippet(_ id: String) throws -> LibrarySnippet { try #require(LibrarySnippets.all.first { $0.id == id }) }

    @Test func catalogIsWellFormed() {
        #expect(Set(LibrarySnippets.all.map(\.id)).count == LibrarySnippets.all.count)
        #expect(Set(LibrarySnippets.all.map(\.category)) == Set(LibrarySnippets.categories))
        for s in LibrarySnippets.all {
            let parsed = Snippet.parse(s.apply)
            #expect(!parsed.text.contains("${"), "\(s.id)")
            #expect(s.plainText == parsed.text)
            #expect(parsed.placeholders.indices.contains(s.selectionStop) || parsed.placeholders.isEmpty, "\(s.id)")
        }
    }

    @Test func codeModeDropsHash() throws {
        #expect(try snippet("footnote").snippet(mode: .code).text == "footnote[]")
        #expect(try snippet("strong").snippet(mode: .code).text == "*text*")
        #expect(try snippet("footnote").snippet(mode: .markup).text == "#footnote[]")
    }

    @Test func mathModeDropsDelimiters() throws {
        #expect(try snippet("inline-math").snippet(mode: .math).text == "x")
        #expect(try snippet("equation").snippet(mode: .math).text == "")
        #expect(try snippet("labeled-equation").snippet(mode: .math).text == "")
        #expect(try snippet("fraction").snippet(mode: .math).text == "(a) / (b)")
        #expect(try snippet("matrix").snippet(mode: .math).text == "mat(1, 0; 0, 1)")
        #expect(try snippet("page-break").snippet(mode: .math).text == "#pagebreak()")
    }

    @Test func selectionWrapsTheRightStop() throws {
        let link = try snippet("link").snippet(mode: .markup, selected: "my words")
        #expect(link.text == "#link(\"https://typst.app\")[my words]")
        #expect((link.text as NSString).substring(with: link.placeholders[1]) == "my words")
        #expect((link.text as NSString).substring(with: link.placeholders[0]) == "https://typst.app")
        let strong = try snippet("strong").snippet(mode: .markup, selected: "hi")
        #expect(strong.text == "*hi*" && strong.selection(insertedAt: 0) == NSRange(location: 1, length: 2))
        let quote = try snippet("quote").snippet(mode: .markup, selected: "}x")
        #expect(quote.text.contains("[\n  }x\n]") && quote.placeholders.count == 2)
        #expect((quote.text as NSString).substring(with: quote.placeholders[1]) == "}x")
        #expect(try snippet("strong").snippet(mode: .markup).text == "*text*")
    }

    @Test func filterRanksAndRemembers() {
        #expect(LibrarySnippets.filter("").map(\.id) == LibrarySnippets.all.map(\.id))
        #expect(LibrarySnippets.filter("", recent: ["grid", "box"]).prefix(3).map(\.id) == ["grid", "box", "heading"])
        let r = LibrarySnippets.filter("figure").map(\.id)
        #expect(r.prefix(3) == ["figure-image", "figure-table", "figure-code"])
        #expect(LibrarySnippets.filter("math").first?.id == "inline-math")
        #expect(LibrarySnippets.filter("zzzz").isEmpty)
    }

    @Test func plainTextResolvesDefaults() throws {
        #expect(try snippet("heading").plainText == "= Title")
        #expect(try snippet("bullet-list").plainText == "- \n- ")
    }

    @Test func plainTextCompiles() async throws {
        let skip: Set<String> = ["figure-image", "bibliography", "import-package", "reference"]
        for s in LibrarySnippets.all where !skip.contains(s.id) {
            let (p, _) = try await TestEnv.project(files: ["main.typ": s.plainText])
            _ = await p.settle()
            #expect(!p.diagnostics.contains { $0.severity == .error }, "\(s.id): \(p.diagnostics)")
        }
    }
}
