import Testing
import TypoTestSupport
@testable import TypoKit

struct CommandPaletteTests {
    func e(_ title: String, _ menu: String, enabled: Bool = true) -> PaletteEntry {
        PaletteEntry(id: "\(menu)/\(title)", title: title, menu: menu, isEnabled: enabled)
    }
    func ids(_ x: [PaletteEntry]) -> [String] { x.map(\.id) }

    @Test func disabledEntriesAreHidden() {
        let all = [e("Bold", "Format"), e("Italic", "Format", enabled: false)]
        #expect(ids(CommandPalette.filter(all, query: "")) == ["Format/Bold"])
        #expect(CommandPalette.filter(all, query: "italic").isEmpty)
    }

    @Test func emptyQueryListsRecentFirst() {
        let all = [e("A", "File"), e("B", "File"), e("C", "File")]
        #expect(ids(CommandPalette.filter(all, query: "  ", recent: ["File/C", "File/B"])) == ["File/C", "File/B", "File/A"])
        #expect(ids(CommandPalette.filter(all, query: "")) == ["File/A", "File/B", "File/C"])
    }

    @Test func everyWordMustMatch() {
        let all = [e("Bullet List", "Format"), e("Numbered List", "Format"), e("Bold", "Format")]
        #expect(ids(CommandPalette.filter(all, query: "list num")) == ["Format/Numbered List"])
        #expect(CommandPalette.filter(all, query: "list zzz").isEmpty)
    }

    @Test func menuNameMatchesRankBelowTitleMatches() {
        let all = [e("Zoom In", "View"), e("Review Changes", "File"), e("Fit Width", "View")]
        #expect(ids(CommandPalette.filter(all, query: "view")) == ["File/Review Changes", "View/Zoom In", "View/Fit Width"])
        #expect(ids(CommandPalette.filter(all, query: "view zoom")) == ["View/Zoom In"])
    }

    @Test func wordPrefixRanksFirst() {
        let all = [e("Unfold Section", "View"), e("Fold Section", "View"), e("Insert Table…", "Format")]
        #expect(ids(CommandPalette.filter(all, query: "fold")) == ["View/Fold Section", "View/Unfold Section"])
        #expect(ids(CommandPalette.filter(all, query: "tab")) == ["Format/Insert Table…"])
    }

    @Test func recentBreaksTiesOnly() {
        let all = [e("Fold Section", "View"), e("Fold All Sections", "View"), e("Unfold All", "View")]
        #expect(ids(CommandPalette.filter(all, query: "fold", recent: ["View/Fold All Sections"])) == ["View/Fold All Sections", "View/Fold Section", "View/Unfold All"])
        #expect(ids(CommandPalette.filter(all, query: "fold", recent: ["View/Unfold All"])) == ["View/Fold Section", "View/Fold All Sections", "View/Unfold All"])
    }

    @Test func caseAndDiacriticsAreIgnored() {
        let all = [e("Café Menü", "File")]
        #expect(ids(CommandPalette.filter(all, query: "CAFE MENU")).count == 1)
        #expect(ids(CommandPalette.filter(all, query: "café")).count == 1)
    }

    @Test func rememberMovesToFrontWithoutDuplicatesAndLimits() {
        #expect(CommandPalette.remember("b", in: ["a", "b", "c"]) == ["b", "a", "c"])
        #expect(CommandPalette.remember("x", in: ["a", "b"], limit: 2) == ["x", "a"])
        #expect(CommandPalette.remember("z", in: (0..<8).map(String.init)).count == 8)
    }
}
