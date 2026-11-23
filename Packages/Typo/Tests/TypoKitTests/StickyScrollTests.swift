import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite(.serialized) @MainActor struct StickyScrollTests {
    static let text = "= A\nintro\n== A1\na1 text\n=== A1x\ndeep\n== A2\na2\n= B\nb\n"
    private func at(_ s: String) -> Int { (Self.text as NSString).range(of: s).location }

    private var regions: [FoldRegion] {
        let ns = Self.text as NSString
        let heads = Folding.candidates(ns).map { (line: ns.lineRange(for: NSRange(location: $0.marker, length: 0)).location, level: $0.level) }
        return Folding.regions(heads, in: ns)
    }

    @Test func pinsTheChainOfSectionsAroundTheTopLineOutermostFirst() {
        #expect(StickyScroll.headings(regions, top: at("intro")).map(\.heading) == [0])
        #expect(StickyScroll.headings(regions, top: at("a1 text")).map(\.heading) == [0, at("== A1")])
        #expect(StickyScroll.headings(regions, top: at("deep")).map(\.heading) == [0, at("== A1"), at("=== A1x")])
        #expect(StickyScroll.headings(regions, top: at("a2")).map(\.heading) == [0, at("== A2")])
        #expect(StickyScroll.headings(regions, top: at("b\n")).map(\.heading) == [at("= B")])
    }

    @Test func aHeadingOnTheTopLineIsVisibleAndNotPinned() {
        #expect(StickyScroll.headings(regions, top: 0).isEmpty)
        #expect(StickyScroll.headings(regions, top: at("== A2")).map(\.heading) == [0])
        #expect(StickyScroll.headings(regions, top: at("= B")).isEmpty)
    }

    @Test func theDepthIsLimitedKeepingTheOutermost() {
        #expect(StickyScroll.headings(regions, top: at("deep"), limit: 2).map(\.heading) == [0, at("== A1")])
        #expect(StickyScroll.headings(regions, top: at("deep"), limit: 0).isEmpty)
    }

    @Test func aBufferPinsRealHeadingsAndTreatsHiddenTextAsItsFoldsLine() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": Self.text])
        let b = try await p.open(RelPath("main.typ")!)
        #expect(b.stickyHeadings(top: at("deep")).map(\.heading) == [0, at("== A1"), at("=== A1x")])
        b.fold([at("== A1")])
        // Folded, `deep` shows on the `== A1` line: only `= A` is above it.
        #expect(b.stickyHeadings(top: at("deep")).map(\.heading) == [0])
    }
}
