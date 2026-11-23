import Testing
import TypoTestSupport
@testable import TypoKit

@Suite struct IssueNavigationTests {
    @Test func nextAndPreviousWrap() {
        let o = [30, 10, 20]
        #expect(IssueNavigation.target(offsets: o, caret: 10, forward: true) == 20)
        #expect(IssueNavigation.target(offsets: o, caret: 30, forward: true) == 10)
        #expect(IssueNavigation.target(offsets: o, caret: 20, forward: false) == 10)
        #expect(IssueNavigation.target(offsets: o, caret: 10, forward: false) == 30)
        #expect(IssueNavigation.target(offsets: [], caret: 0, forward: true) == nil)
    }
}
