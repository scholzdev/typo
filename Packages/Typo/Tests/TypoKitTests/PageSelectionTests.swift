import PDFKit
import Testing
import TypoTestSupport
import TypstEngine
@testable import TypoKit

struct PageSelectionTests {
    func spans(_ s: String, of n: Int = 10) -> [PageSpan]? { try? PageSelection.parse(s, pageCount: n)?.get() }
    func failure(_ s: String, of n: Int = 10) -> String? {
        if case .failure(let f) = PageSelection.parse(s, pageCount: n) { f.message } else { nil }
    }

    @Test func emptyMeansEveryPage() {
        #expect(PageSelection.parse("", pageCount: 5) == nil)
        #expect(PageSelection.parse("  ", pageCount: 5) == nil)
    }

    @Test func pagesRangesAndOpenEnds() {
        #expect(spans("3") == [PageSpan(first: 3, last: 3)])
        #expect(spans("1-3, 7 9–") == [PageSpan(first: 1, last: 3), PageSpan(first: 7, last: 7), PageSpan(first: 9, last: nil)])
        #expect(spans("-2") == [PageSpan(first: nil, last: 2)])
    }

    @Test func refusesWhatTypstWouldMisread() {
        #expect(failure("0") != nil)
        #expect(failure("a") != nil)
        #expect(failure("-") != nil)
        #expect(failure("5-2") == "“5-2” runs backwards.")
        #expect(failure("12", of: 10) == "The document has 10 pages, so there is no page 12.")
    }

    @MainActor @Test func exportsOnlyTheChosenPages() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "A\n#pagebreak()\nB\n#pagebreak()\nC"])
        let pdf = try await p.exportPDF(pages: [PageSpan(first: 2, last: nil)])
        let doc = try #require(PDFDocument(data: pdf))
        #expect(doc.pageCount == 2)
        #expect(doc.page(at: 0)?.string?.contains("B") == true)
    }
}
