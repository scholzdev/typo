import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite struct BibTeXTests {
    let sample = """
    % my refs
    @string{tub = "TU Berlin"}

    @book{knuth84,
      author    = {Donald E. Knuth},
      title     = {The {TeX}book},
      year      = 1984,
    }

    @article(madje2022,
      author = "Laurenz M{\\"a}dje",
      school = tub # " Berlin",
      journal = {X}
    )

    @misc{typstdocs,
      author = {{Typst GmbH}},
    }

    """

    @Test func parsesFieldsAndSkipsSpecialEntries() throws {
        let es = BibTeX.entries(in: sample)
        #expect(es.map(\.key) == ["knuth84", "madje2022", "typstdocs"])
        #expect(es[0].type == "book")
        #expect(es[0].fields == [.init(name: "author", value: "Donald E. Knuth"), .init(name: "title", value: "The {TeX}book"),
                                 .init(name: "year", value: "1984", isRaw: true)])
        #expect(es[1].value("author") == "Laurenz M{\\\"a}dje")
        #expect(es[1].fields[1] == .init(name: "school", value: "tub # \" Berlin\"", isRaw: true))
        #expect(es[2].value("author") == "{Typst GmbH}")
        let s = sample as NSString
        #expect(s.substring(with: es[2].range).hasPrefix("@misc{") && s.substring(with: es[2].range).hasSuffix("}"))
    }

    @Test func updateRewritesOnlyThatEntry() {
        var e = BibTeX.entries(in: sample)[0]
        e.fields[1].value = "The TeXbook"
        e.fields.append(.init(name: "publisher", value: "Addison-Wesley"))
        let r = BibTeX.update(e)
        let out = (sample as NSString).replacingCharacters(in: r.range, with: r.text)
        #expect(out.contains("""
        @book{knuth84,
          author    = {Donald E. Knuth},
          title     = {The TeXbook},
          year      = 1984,
          publisher = {Addison-Wesley},
        }
        """))
        #expect(out.hasPrefix("% my refs\n@string{tub = \"TU Berlin\"}\n\n@book"))
        #expect(BibTeX.entries(in: out).map(\.key) == ["knuth84", "madje2022", "typstdocs"])
    }

    @Test func removalKeepsOneBlankLine() {
        let es = BibTeX.entries(in: sample)
        let apply = { (r: Replacement) in (sample as NSString).replacingCharacters(in: r.range, with: r.text) }
        let middle = apply(BibTeX.removal(es[1], in: sample))
        #expect(middle.contains("}\n\n@misc{typstdocs"))
        let last = apply(BibTeX.removal(es[2], in: sample))
        #expect(last.hasSuffix("\n)\n"))
        #expect(BibTeX.entries(in: last).map(\.key) == ["knuth84", "madje2022"])
    }

    @Test func appendAndHelpers() {
        let e = BibTeXEntry(type: "article", key: BibTeX.uniqueKey("knuth84", used: ["knuth84", "knuth842"]),
                            fields: [.init(name: "title", value: "")])
        let r = BibTeX.append(e, to: "@misc{a,\n}")
        #expect(r.text == "\n\n@article{knuth843,\n  title = {},\n}\n")
        #expect(BibTeX.isBalanced("a {b} \\{"))
        #expect(!BibTeX.isBalanced("a {b"))
        #expect(!BibTeX.isBalanced("}{"))
        #expect(BibTeX.isFormEditable("refs.BIB") && !BibTeX.isFormEditable("refs.yml"))
    }

    @Test func suggestsSurnameYearKeys() {
        #expect(BibTeX.suggestedKey(author: "Donald E. Knuth", year: "1984") == "knuth1984")
        #expect(BibTeX.suggestedKey(author: "Mädje, Laurenz and Haug, Martin", year: "c. 2022") == "madje2022")
        #expect(BibTeX.suggestedKey(author: "Knuth", year: "") == "knuth")
        #expect(BibTeX.suggestedKey(author: " ", year: "2020") == nil)
        #expect(BibTeX.suggestedFields(for: "article").prefix(3) == ["author", "title", "journal"])
        #expect(!BibTeX.optionalFields(for: "online").contains("url"))
    }

    @Test func requiredFieldsAcceptAlternatives() {
        #expect(BibTeX.missingRequired(type: "book", present: ["author", "title", "publisher", "year"]).isEmpty)
        #expect(BibTeX.missingRequired(type: "book", present: ["editor", "title", "publisher", "date"]).isEmpty)
        #expect(BibTeX.missingRequired(type: "book", present: ["title"]) == ["author", "editor", "publisher", "year", "date"])
        #expect(BibTeX.missingRequired(type: "misc", present: []).isEmpty)
    }
}
