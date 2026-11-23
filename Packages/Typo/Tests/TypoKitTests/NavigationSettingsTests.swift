import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite struct NavigationSettingsTests {
    private let a = RelPath("a.typ")!, b = RelPath("b.typ")!, c = RelPath("c.typ")!

    @Test func automaticPinningNeverCreatesAPreviewTab() {
        var t = TabList()
        t.show(a, permanent: false, pinning: .automatically)
        t.show(b, permanent: false, pinning: .automatically)
        #expect(t.paths == [a, b])
        #expect(t.preview == nil)
        var m = TabList()
        m.show(a, permanent: false)
        m.show(b, permanent: false)
        #expect(m.paths == [b] && m.preview == b)
    }

    @Test func standardIsTodaysBehaviour() {
        let s = NavigationSettings.standard
        #expect(s.pinTabs == .manually && s.commandClick == .jump && s.optionClick == .quickHelp)
        #expect(s.destination == .primary && s.doubleClickOpensPermanent)
    }

    @Test func destinationResolution() {
        var s = NavigationSettings.standard
        // Primary: always the first pane.
        for second in [nil, b] as [RelPath?] { #expect(s.pane(for: c, first: a, focusedSecond: second) == .first) }
        s.destination = .focused
        // Split closed or first pane focused (focusedSecond nil): first pane.
        #expect(s.pane(for: c, first: a, focusedSecond: nil) == .first)
        #expect(s.pane(for: b, first: a, focusedSecond: nil) == .first)
        // Second pane focused: another file, or its own file, opens there; the first pane's file stays.
        #expect(s.pane(for: c, first: a, focusedSecond: b) == .second)
        #expect(s.pane(for: b, first: a, focusedSecond: b) == .second)
        #expect(s.pane(for: a, first: a, focusedSecond: b) == .first)
    }

    @Test func clickActionsSelectableForBothModifiers() {
        var s = NavigationSettings.standard
        s.commandClick = .quickHelp
        s.optionClick = .none
        #expect(s.commandClick == .quickHelp && s.optionClick == .none)
        #expect(NavigationSettings.ClickAction(rawValue: "jump") == .jump && NavigationSettings.ClickAction(rawValue: "x") == nil)
    }
}
