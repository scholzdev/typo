import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite struct MinimapTests {
    static let text = "= Intro\n  #let x = 1\n\tab\n== Last"
    private func at(_ s: String) -> Int { (Self.text as NSString).range(of: s).location }
    private var headings: [(line: Int, level: Int)] { [(0, 1), (at("== Last"), 2)] }

    @Test func linesCarryIndentMergedRunsAndHeadings() {
        // `#let` and `x` share colour 1, `= 1` is colour 2; the blank between same-coloured words stays inside the run.
        let runs = [MinimapModel.ColorRun(range: NSRange(location: at("#let"), length: 7), color: 1),
                    MinimapModel.ColorRun(range: NSRange(location: at("= 1"), length: 3), color: 2)]
        let m = MinimapModel.build(text: Self.text, runs: runs, headings: headings, hidden: [])
        #expect(m.lines.map(\.number) == [0, 1, 2, 3])
        #expect(m.lines.map(\.offset) == [0, at("  #let"), at("\tab"), at("== Last")])
        #expect(m.lines[1].indent == 2)
        #expect(m.lines[1].runs == [.init(column: 2, length: 6, color: 1), .init(column: 9, length: 3, color: 2)])
        #expect(m.lines[2].runs == [.init(column: 4, length: 2, color: 0)])     // a tab is four columns
        #expect(m.lines[0].heading == .init(level: 1, title: "Intro"))
        #expect(m.lines[1].heading == nil)
        // A heading on the last line, with no section after it, is still there.
        #expect(m.lines[3].heading == .init(level: 2, title: "Last"))
        #expect(m.heading(containing: 2)?.title == "Intro")
        #expect(m.heading(containing: 3)?.title == "Last")
    }

    @Test func foldedLinesLeaveTheMapAndMapToTheirHeading() {
        let text = "= A\na1\na2\n= B\nb\n"
        let ns = text as NSString
        let hidden = NSRange(location: ns.range(of: "a1").location, length: ns.range(of: "= B").location - ns.range(of: "a1").location)
        let m = MinimapModel.build(text: text, runs: [], headings: [(0, 1), (ns.range(of: "= B").location, 1)], hidden: [hidden])
        #expect(m.lines.map(\.number) == [0, 3, 4, 5])
        #expect(m.lineIndex(of: ns.range(of: "a2").location) == 0)
        #expect(m.lineIndex(of: ns.range(of: "b").location) == 2)
        // A folded last section hides the empty line after the final break too.
        let tail = NSRange(location: ns.range(of: "b").location, length: 2)
        #expect(MinimapModel.build(text: text, runs: [], headings: [], hidden: [tail]).lines.map(\.number) == [0, 1, 2, 3])
    }

    @Test func shortDocumentDoesNotScroll() {
        let g = MinimapGeometry(lineCount: 50, lineHeight: 2, viewHeight: 400)
        #expect(g.offset(top: 0, visible: 20) == 0)
        #expect(g.offset(top: 30, visible: 20) == 0)
        #expect(g.band(top: 10, visible: 20) == (20, 40))
        #expect(g.line(atY: 60, top: 10, visible: 20) == 30)
        #expect(g.top(centering: 60, top: 10, visible: 20) == 20)
        #expect(g.top(forBandY: 20, visible: 20) == 10)
        #expect(g.top(forBandY: 500, visible: 20) == 30)    // clamped to the last screenful
    }

    @Test func longDocumentScrollsInProportion() {
        // 1000 lines of 2 pt in 400 pt: 1600 pt of overflow over 950 lines of editor travel.
        let g = MinimapGeometry(lineCount: 1000, lineHeight: 2, viewHeight: 400)
        #expect(g.offset(top: 0, visible: 50) == 0)
        #expect(g.band(top: 0, visible: 50) == (0, 100))
        #expect(g.offset(top: 475, visible: 50) == 800)
        #expect(g.band(top: 475, visible: 50).y == 150)       // middle: the band is mid-view
        #expect(g.offset(top: 950, visible: 50) == 1600)
        #expect(g.band(top: 950, visible: 50) == (300, 100))  // bottom: the band ends at the view's bottom
        // Inverse: dragging the band back to where `band` put it gives the same top line.
        for t in [0.0, 475, 950] {
            #expect(abs(g.top(forBandY: g.band(top: t, visible: 50).y, visible: 50) - t) < 1e-9)
        }
        // A click at the view's middle while at the top centres line 100 (y 200 + offset 0).
        #expect(g.top(centering: 200, top: 0, visible: 50) == 75)
        // At the middle the same click hits line (200 + 800) / 2 = 500.
        #expect(g.top(centering: 200, top: 475, visible: 50) == 475)
    }

    @MainActor @Test func headingLinesIncludeOneWithoutASection() async throws {
        let text = "= A\nx\n= Last"
        let (p, _) = try await TestEnv.project(files: ["main.typ": text])
        let b = try await p.open(RelPath("main.typ")!)
        #expect(b.headingLines.map(\.line) == [0, 6])
        #expect(b.foldRegions.map(\.heading) == [0])
    }
}
