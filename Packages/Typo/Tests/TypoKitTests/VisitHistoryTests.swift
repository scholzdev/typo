import Testing
import TypoTestSupport
@testable import TypoKit

@Suite struct VisitHistoryTests {
    @Test func backAndForwardWalkTheVisits() {
        var h = VisitHistory(start: 1)
        h.visit(2); h.visit(3)
        #expect(h.back() == 2)
        #expect(h.back() == 1)
        #expect(h.back() == nil && !h.canGoBack)
        #expect(h.forward() == 2)
        #expect(h.forward() == 3)
        #expect(h.forward() == nil && !h.canGoForward)
    }

    @Test func visitAfterBackDropsForwardAndRepeatsAreIgnored() {
        var h = VisitHistory(start: 1)
        h.visit(2); h.visit(2); h.visit(3)
        _ = h.back(); _ = h.back()
        h.visit(4)
        #expect(!h.canGoForward)
        #expect(h.back() == 1)
        #expect(h.forward() == 4)
    }
}
