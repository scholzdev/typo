import CoreGraphics
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite struct EditorDecorTests {
    @Test func badges() {
        #expect(CompletionBadge.letters(for: .function) == "F")
        #expect(CompletionBadge.letters(for: .path) == "Pa")
        #expect(CompletionBadge.letters(for: .package) == "Pk")
        #expect(CompletionBadge.letters(for: .font) == "Fo")
        #expect(CompletionBadge.letters(for: .symbol("α")) == nil)
        let kinds: [CompletionKind] = [.syntax, .function, .type, .parameter, .constant, .path, .package, .label, .font]
        #expect(Set(kinds.compactMap(CompletionBadge.letters(for:))).count == kinds.count)
    }

    @Test func matchIndices() {
        #expect(CompletionMatch.indices(of: "He", in: "heading") == [0, 1])
        #expect(CompletionMatch.indices(of: "hdg", in: "heading") == [0, 3, 6])
        #expect(CompletionMatch.indices(of: "", in: "heading").isEmpty)
        #expect(CompletionMatch.indices(of: "xyz", in: "heading").isEmpty)
    }

    @Test func pillGrouping() {
        let pills = PillLayout.pills([(2, false, "w"), (2, true, "e1\ndetail"), (2, true, "e2"), (5, false, "w2")])
        #expect(pills == [LinePill(line: 2, error: true, message: "e1", more: 2), LinePill(line: 5, error: false, message: "w2", more: 0)])
    }

    @Test func pillTruncation() {
        let measure: (String) -> CGFloat = { CGFloat($0.count) }
        let p = LinePill(line: 0, error: true, message: "unknown variable", more: 2)
        #expect(PillLayout.text(p, fitting: 100, measure: measure) == "unknown variable  +2")
        #expect(PillLayout.text(p, fitting: 10, measure: measure) == "unkno…  +2")
        #expect(PillLayout.text(p, fitting: 3, measure: measure) == nil)
        let single = LinePill(line: 0, error: false, message: "abcdef", more: 0)
        #expect(PillLayout.text(single, fitting: 4, measure: measure) == "abc…")
    }

    @Test func selectionLineRects() {
        let rects = SelectionShape.lineRects([CGRect(x: 50, y: 0, width: 10, height: 16), CGRect(x: 0, y: 0, width: 20, height: 16),
                                              CGRect(x: 0, y: 16, width: 30, height: 16)])
        #expect(rects == [CGRect(x: 0, y: 0, width: 60, height: 16), CGRect(x: 0, y: 16, width: 30, height: 16)])
    }
}
