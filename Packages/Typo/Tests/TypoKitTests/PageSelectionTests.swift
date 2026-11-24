import PDFKit
import Testing
import TypoTestSupport
import TypstEngine
@testable import TypoKit

struct PageSelectionTests {
    @Test func everyPageExportsWhole() {
        #expect(PageSelection.all.spans(pageCount: 5) == nil)
        #expect(PageSelection.range(from: 1, to: 5).spans(pageCount: 5) == nil)
        #expect(PageSelection.pages([1, 2, 3]).spans(pageCount: 3) == nil)
    }

    @Test func rangesAreClampedAndOrdered() {
        #expect(PageSelection.range(from: 2, to: 3).spans(pageCount: 5) == [PageSpan(first: 2, last: 3)])
        #expect(PageSelection.range(from: 4, to: 2).spans(pageCount: 5) == [PageSpan(first: 2, last: 4)])
        #expect(PageSelection.range(from: 3, to: 99).spans(pageCount: 5) == [PageSpan(first: 3, last: 5)])
    }

    @Test func tickedPagesBecomeRuns() {
        #expect(PageSelection.pages([1, 2, 4, 6, 7]).spans(pageCount: 8)
                == [PageSpan(first: 1, last: 2), PageSpan(first: 4, last: 4), PageSpan(first: 6, last: 7)])
        #expect(PageSelection.pages([]).spans(pageCount: 3) == [])
        #expect(PageSelection.pages([9]).spans(pageCount: 3) == [])
    }

    @MainActor @Test func exportsOnlyTheChosenPages() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "A\n#pagebreak()\nB\n#pagebreak()\nC"])
        let pdf = try await p.exportPDF(pages: PageSelection.pages([1, 3]).spans(pageCount: 3))
        let doc = try #require(PDFDocument(data: pdf))
        #expect(doc.pageCount == 2)
        #expect(doc.page(at: 1)?.string?.contains("C") == true)
    }
}
