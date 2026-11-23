import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite(.serialized) @MainActor struct ReferenceTests {
    // MARK: Parsing

    @Test func parsesDOIForms() {
        let doi = ReferenceID.doi("10.1145/3591280")
        for s in ["10.1145/3591280", "doi:10.1145/3591280", "DOI: 10.1145/3591280", "https://doi.org/10.1145/3591280",
                  "http://dx.doi.org/10.1145/3591280", "  https://doi.org/10.1145%2F3591280\n"] {
            #expect(ReferenceID.parse(s) == doi, "\(s)")
        }
        for s in ["", "10.12/abc", "11.1145/3591280", "https://example.com/10.1145/3591280", "hello"] {
            #expect(ReferenceID.parse(s) == nil, "\(s)")
        }
    }

    @Test func parsesISBNsWithChecksum() {
        #expect(ReferenceID.parse("978-0-201-03801-9") == .isbn("9780201038019"))
        #expect(ReferenceID.parse("ISBN 978 0 201 03801 9") == .isbn("9780201038019"))
        #expect(ReferenceID.parse("0-201-03801-3") == .isbn("0201038013"))
        #expect(ReferenceID.parse("0-8044-2957-X") == .isbn("080442957X"))
        #expect(ReferenceID.parse("978-0-201-03801-6") == nil)      // bad checksum
        #expect(ReferenceID.parse("0-201-03801-4") == nil)
        #expect(ReferenceID.parse("12345") == nil)
        #expect(ReferenceID.isbn13("0201038013") == "9780201038019")
    }

    @Test func parsesArXivForms() {
        for s in ["2101.00001", "arXiv:2101.00001", "ARXIV: 2101.00001v3", "https://arxiv.org/abs/2101.00001",
                  "https://arxiv.org/pdf/2101.00001v2.pdf", "http://export.arxiv.org/abs/2101.00001/", "  arXiv:2101.00001\n"] {
            #expect(ReferenceID.parse(s) == .arxiv("2101.00001"), "\(s)")
        }
        #expect(ReferenceID.parse("1706.03762") == .arxiv("1706.03762"))
        #expect(ReferenceID.parse("hep-th/9901001v1") == .arxiv("hep-th/9901001"))
        #expect(ReferenceID.parse("arXiv:math.GT/0309136") == .arxiv("math.GT/0309136"))
        #expect(ReferenceID.parse("10.48550/arXiv.2101.00001") == .doi("10.48550/arXiv.2101.00001"))
        for s in ["2101.001", "arXiv:", "https://arxiv.org/list/cs", "21010.00001"] { #expect(ReferenceID.parse(s) == nil, "\(s)") }
    }

    // MARK: Fetching

    private func stub(_ body: String, status: Int = 200, seen: Box? = nil) -> ReferenceFetch {
        { req in seen?.request = req; return (Data(body.utf8), status) }
    }
    final class Box: @unchecked Sendable { var request: URLRequest? }

    @Test func doiRequestAndKeyKept() async throws {
        let seen = Box()
        let bib = "@article{Smith_2023, title={Deep Things}, volume={1}, author={Smith, Jane and Doe, John}, year={2023}}"
        let d = try await ReferenceLookup.fetch(.doi("10.1145/3591280"), usedKeys: ["other"], via: stub(bib, seen: seen))
        #expect(d.key == "Smith_2023")
        #expect(d.entry.title == "Deep Things")
        #expect(d.entry.year == 2023)
        let r = try #require(seen.request)
        #expect(r.url?.absoluteString == "https://doi.org/10.1145/3591280")
        #expect(r.value(forHTTPHeaderField: "Accept") == "application/x-bibtex; charset=utf-8")
        #expect(r.value(forHTTPHeaderField: "User-Agent") == "Typo/0.1")
        #expect(r.timeoutInterval == 20)
    }

    @Test func collidingKeyBecomesAuthorYearWithSuffix() async throws {
        let bib = "@article{Smith_2023, title={Deep Things}, author={Müller, Jörg and Doe, John}, year={2023}}"
        let a = try await ReferenceLookup.fetch(.doi("10.1/abcd"), usedKeys: ["Smith_2023"], via: stub(bib))
        #expect(a.key == "muller2023")
        #expect(a.bibtex.hasPrefix("@article{muller2023,"))
        let b = try await ReferenceLookup.fetch(.doi("10.1/abcd"), usedKeys: ["Smith_2023", "muller2023", "muller2023a"], via: stub(bib))
        #expect(b.key == "muller2023b")
        #expect(throws: ReferenceError.keyInUse("muller2023b")) { try a.rekeyed("muller2023b", usedKeys: ["muller2023b"]) }
        #expect(throws: ReferenceError.invalidKey("bad key")) { try a.rekeyed("bad key", usedKeys: []) }
        #expect(try a.rekeyed("mine", usedKeys: []).bibtex.hasPrefix("@article{mine,"))
    }

    @Test func invalidFetchedKeyIsReplaced() async throws {
        let bib = "@misc{10.5281/zenodo.1, title={Data}, author={Ada Lovelace}, year={2024}}"
        let d = try await ReferenceLookup.fetch(.doi("10.5281/zenodo.1"), usedKeys: [], via: stub(bib))
        #expect(d.key == "lovelace2024" || d.key == "ref2024")
    }

    @Test func fetchErrorsAreReadable() async {
        await #expect(throws: ReferenceError.notFound) { try await ReferenceLookup.fetch(.doi("10.1/x1x1"), usedKeys: [], via: stub("", status: 404)) }
        await #expect(throws: ReferenceError.offline) { try await ReferenceLookup.fetch(.doi("10.1/x1x1"), usedKeys: [], via: { _ in throw URLError(.notConnectedToInternet) }) }
        await #expect(throws: ReferenceError.self) { try await ReferenceLookup.fetch(.doi("10.1/x1x1"), usedKeys: [], via: stub("<html>nope</html>")) }
        await #expect(throws: ReferenceError.notFound) { try await ReferenceLookup.fetch(.isbn("9780201038019"), usedKeys: [], via: stub("{}")) }
    }

    @Test func arXivGoesThroughItsDataCiteDOIWithAFreshKey() async throws {
        let seen = Box()
        let bib = """
        @misc{https://doi.org/10.48550/arxiv.1706.03762,
          doi = {10.48550/ARXIV.1706.03762},
          author = {Vaswani, Ashish and Shazeer, Noam},
          title = {Attention Is All You Need},
          publisher = {arXiv},
          year = {2017}
        }
        """
        let d = try await ReferenceLookup.fetch(.arxiv("1706.03762"), usedKeys: ["vaswani2017"], via: stub(bib, seen: seen))
        #expect(seen.request?.url?.absoluteString == "https://doi.org/10.48550/arXiv.1706.03762")
        #expect(d.key == "vaswani2017a")
        #expect(d.bibtex.hasPrefix("@misc{vaswani2017a,"))
        #expect(d.entry.title == "Attention Is All You Need")
        await #expect(throws: ReferenceError.notFound) { try await ReferenceLookup.fetch(.arxiv("2101.99999"), usedKeys: [], via: stub("", status: 404)) }
    }

    @Test func isbnBuildsABookEntry() async throws {
        let seen = Box()
        let json = """
        {"ISBN:9780201038019": {"title": "The Art of Computer Programming", "subtitle": "Fundamental Algorithms",
         "authors": [{"name": "Donald E. Knuth"}, {"name": "Jane Roe"}], "publishers": [{"name": "Addison-Wesley"}], "publish_date": "March 1, 1997"}}
        """
        let d = try await ReferenceLookup.fetch(.isbn("9780201038019"), usedKeys: ["knuth1997"], via: stub(json, seen: seen))
        #expect(seen.request?.url?.absoluteString == "https://openlibrary.org/api/books?bibkeys=ISBN:9780201038019&format=json&jscmd=data")
        #expect(d.key == "knuth1997a")
        #expect(d.entry.kind == "Book")
        #expect(d.entry.title == "The Art of Computer Programming: Fundamental Algorithms")
        #expect(d.entry.year == 1997)
        #expect(d.bibtex.contains("author = {Knuth, Donald E. and Roe, Jane}"))
        #expect(d.bibtex.contains("isbn = {9780201038019}"))
    }

    // MARK: Target and writing

    private func draft(_ key: String = "new2024") throws -> ReferenceDraft {
        try ReferenceDraft.make(bibtex: "@book{\(key), title={T}, author={Doe, John}, year={2024}}\n", usedKeys: [])
    }

    @Test func singleBibIsTheTarget() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "= x\n", "a.bib": ""])
        #expect(p.referenceTargets().preferred == RelPath("a.bib"))
    }

    @Test func severalBibsPreferTheOneNamedInBibliography() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "#let b = \"a.bib\"\n#bibliography(\"lit/x.bib\")\n", "a.bib": "", "lit/x.bib": ""])
        let t = p.referenceTargets()
        #expect(Set(t.candidates.map(\.raw)) == ["a.bib", "lit/x.bib"])
        #expect(t.preferred == RelPath("lit/x.bib"))
        let (q, _) = try await TestEnv.project(files: ["main.typ": "= x\n", "a.bib": "", "b.bib": ""])
        #expect(q.referenceTargets().preferred == nil)
    }

    @Test func addingAppendsToTheBufferAsOneUndoStep() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "= x\n", "refs.bib": "@book{old, title={O}, year={2000}}\n"])
        let bib = try await p.open(RelPath("refs.bib")!)
        let before = bib.storage.string
        try await p.addReference(try draft(), to: RelPath("refs.bib")!)
        #expect(bib.storage.string == before + "\n@book{new2024, title={T}, author={Doe, John}, year={2024}}\n")
        #expect(await p.references().first?.entries.map(\.key) == ["old", "new2024"])
        bib.undoManager.undo()
        #expect(bib.storage.string == before)
        #expect(try String(contentsOf: root.appending(path: "refs.bib"), encoding: .utf8) == before)   // never written behind the buffer
    }

    @Test func noBibCreatesRefsBibAndAppendsBibliographyToMain() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "= x"])
        #expect(p.referenceTargets().candidates.isEmpty)
        let path = try await p.addReference(try draft(), to: nil, appendBibliography: true)
        #expect(path.raw == "refs.bib")
        #expect(p.allFiles.contains(path))
        #expect(await p.usedReferenceKeys() == ["new2024"])
        let main = try await p.open(p.main)
        #expect(main.storage.string == "= x\n\n#bibliography(\"refs.bib\")\n")
        main.undoManager.undo()
        #expect(main.storage.string == "= x")
    }

    // MARK: Completion detail

    @Test func completionDetailShowsAuthorsYearTitleForBibKeys() async throws {
        let (p, _) = try await TestEnv.project("demo", main: "ui-test.typ")
        let b = try await p.open(RelPath("ui-test.typ")!)
        let at = b.storage.length
        replace(b, NSRange(location: at, length: 0), with: "\nSiehe @")
        var detail: String?
        for _ in 0..<40 where detail == nil {
            if let list = await p.complete(in: b.path, at: b.storage.length, explicit: true) {
                detail = list.items.first { $0.label == "knuth84" }?.detail
                if detail?.hasPrefix("Donald") == true { break }
                detail = nil
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        #expect(detail == "Donald E. Knuth (1984): The TeXbook")
    }

    @Test func severalCitationsJoinPerMode() {
        #expect(BibliographyFile.citations(["a", "b"], mode: .markup) == "@a @b")
        #expect(BibliographyFile.citations(["a", "b"], mode: .code) == "cite(<a>), cite(<b>)")
        #expect(BibliographyFile.citations(["a", "b"], mode: .math) == "cite(<a>) cite(<b>)")
    }

    @Test func entryFilterMatchesAnyField() {
        let e = BibEntry(key: "knuth84", title: "The TeXbook", authors: "Donald E. Knuth", year: 1984, kind: "Book")
        for q in ["", "KNUTH", "texbook", "1984", "book", " donald "] { #expect(e.matches(q), "\(q)") }
        #expect(!e.matches("lamport"))
    }

    @Test func detailOmitsMissingParts() {
        #expect(BibEntry(key: "k", title: "T", authors: "", year: nil, kind: "Misc").completionDetail == "T")
        #expect(BibEntry(key: "k", title: "T", authors: "A B", year: nil, kind: "Misc").completionDetail == "A B: T")
    }
}
