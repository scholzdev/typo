import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite struct BibliographyTests {
    // MARK: Files

    @Test func recognizesBibAndHayagrivaFiles() {
        for p in ["refs.bib", "lit/Refs.BIB", "works.yml", "a/works.yaml"] { #expect(BibliographyFile.isBibliography(p), "\(p)") }
        for p in ["main.typ", "bib", "refs.bib.txt", "data.json"] { #expect(!BibliographyFile.isBibliography(p), "\(p)") }
    }

    @Test func parsesBibTeX() throws {
        let f = BibliographyFile.parse(RelPath("refs.bib")!, text: """
            @book{knuth84, title={The {TeX}book}, author={Knuth, Donald E.}, year={1984}}
            @article{a2, title={Second}, author={Roe, Jane and Doe, John}, journal={J}, year={2020}}
            """)
        #expect(f.error == nil)
        #expect(f.entries.map(\.key) == ["knuth84", "a2"])
        let k = try #require(f.entries.first)
        #expect(k.title == "The TeXbook")
        #expect(k.authors == "Donald E. Knuth")
        #expect(k.year == 1984)
        #expect(k.kind == "Book")
    }

    @Test func parsesHayagrivaYAML() {
        let f = BibliographyFile.parse(RelPath("works.yml")!, text: """
            knuth84:
              type: Book
              title: The TeXbook
              author: Knuth, Donald E.
              date: 1984
            """)
        #expect(f.error == nil)
        #expect(f.entries.map(\.key) == ["knuth84"])
        #expect(f.entries.first?.year == 1984)
    }

    @Test func brokenFileReportsAnError() {
        #expect(BibliographyFile.parse(RelPath("refs.bib")!, text: "@book{x, title={unclosed").error != nil)
        #expect(BibliographyFile.parse(RelPath("works.yml")!, text: "x: [unclosed").error != nil)
    }

    // MARK: Citations

    @Test func citationFollowsTheMode() {
        #expect(BibliographyFile.citation("k", mode: .markup) == "@k")
        #expect(BibliographyFile.citation("k", mode: .text) == "@k")
        #expect(BibliographyFile.citation("k", mode: .code) == "cite(<k>)")
        #expect(BibliographyFile.citation("k", mode: .math) == "cite(<k>)")
        #expect(BibliographyFile.citations([], mode: .markup) == "")
        #expect(BibliographyFile.citations(["k"], mode: .code) == "cite(<k>)")
    }

    @Test func detailHasAllParts() {
        let e = BibEntry(key: "k", title: "T", authors: "A B", year: 2020, kind: "Book")
        #expect(e.completionDetail == "A B (2020): T")
        #expect(BibEntry(key: "k", title: "", authors: "", year: 2020, kind: "Book").completionDetail == "(2020)")
    }

    // MARK: Duplicates

    private func entries(_ s: String) -> [BibTeXEntry] { BibTeX.entries(in: s) }

    @Test func sameKeyIsADuplicate() {
        let es = entries("@book{a, title={One}}\n@book{b, title={Two}}\n@misc{a, title={Three}}")
        #expect(BibTeX.duplicates(es) == [2: "a"])
    }

    @Test func sameDOIIgnoringCaseAndURLFormIsADuplicate() {
        let es = entries("""
            @article{x, doi={10.1145/ABC}}
            @article{y, doi={https://doi.org/10.1145/abc}}
            @article{z, doi={10.1145/other}}
            """)
        #expect(BibTeX.duplicates(es) == [1: "x"])
    }

    @Test func arXivDOIMatchesEprint() {
        let es = entries("""
            @misc{vaswani2017, doi={10.48550/ARXIV.1706.03762}, title={Attention Is All You Need}, year={2017}}
            @article{attn, eprint={1706.03762v5}, archiveprefix={arXiv}, title={Attention}}
            """)
        #expect(BibTeX.duplicates(es) == [1: "vaswani2017"])
    }

    @Test func isbn10MatchesIsbn13() {
        let es = entries("@book{a, isbn={0-201-03801-3}}\n@book{b, isbn={978-0-201-03801-9}}")
        #expect(BibTeX.duplicates(es) == [1: "a"])
    }

    @Test func titleAndYearMatchIgnoringCaseBracesAndPunctuation() {
        let es = entries("""
            @book{a, title={The {TeX}book: A Guide}, year={1984}}
            @book{b, title={the texbook -- a guide}, year={1984}}
            @book{c, title={The TeXbook: A Guide}, year={1986}}
            @book{d, title={Notes}, year={2000}}
            @book{e, title={Notes}, year={2000}}
            """)
        #expect(BibTeX.duplicates(es) == [1: "a"])     // another year is another edition; short titles never match
    }

    @MainActor @Test func existingReferenceIsFoundInAnyBibOfTheProject() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "= x\n", "a.bib": "@book{old, title={Other}}\n",
                                                        "lit/b.bib": "@misc{attn, doi={10.48550/arXiv.1706.03762}}\n"])
        let same = try ReferenceDraft.make(bibtex: "@misc{x, title={Attention Is All You Need}, eprint={1706.03762}, year={2017}}\n", usedKeys: [])
        let hit = try #require(p.existingReference(for: same))
        #expect(hit.key == "attn")
        #expect(hit.file == RelPath("lit/b.bib"))
        let other = try ReferenceDraft.make(bibtex: "@misc{y, title={Something Else Entirely}, year={2017}}\n", usedKeys: [])
        #expect(p.existingReference(for: other) == nil)
    }
}
