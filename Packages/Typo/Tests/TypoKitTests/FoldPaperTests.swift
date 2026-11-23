import CoreGraphics
import QuartzCore
import Testing
import TypoTestSupport
@testable import TypoKit

@Suite struct FoldPaperTests {
    @Test func easingStartsAndEndsAtRestAndIsSymmetric() {
        #expect(FoldPaper.eased(0) == 0 && FoldPaper.eased(1) == 1)
        #expect(FoldPaper.eased(-1) == 0 && FoldPaper.eased(2) == 1)
        #expect(abs(FoldPaper.eased(0.5) - 0.5) < 1e-9)
        #expect(abs(FoldPaper.eased(0.2) + FoldPaper.eased(0.8) - 1) < 1e-9)
        let steps = (0...20).map { FoldPaper.eased(Double($0) / 20) }
        #expect(zip(steps, steps.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test func heightShrinksWhenFoldingAndGrowsWhenUnfolding() {
        #expect(FoldPaper.height(full: 200, eased: 0, folding: true) == 200)
        #expect(FoldPaper.height(full: 200, eased: 1, folding: true) == 0)
        #expect(FoldPaper.height(full: 200, eased: 0, folding: false) == 0)
        #expect(FoldPaper.height(full: 200, eased: 0.25, folding: false) == 50)
    }

    @Test func angleIsTheArcCosineOfTheShownFraction() {
        #expect(FoldPaper.angle(current: 200, full: 200) == 0)
        #expect(abs(FoldPaper.angle(current: 0, full: 200) - .pi / 2) < 1e-9)
        #expect(abs(FoldPaper.angle(current: 100, full: 200) - .pi / 3) < 1e-9)
        #expect(FoldPaper.angle(current: 300, full: 200) == 0)          // clamped
        #expect(FoldPaper.angle(current: 5, full: 0) == .pi / 2)
    }

    /// The hinges stay on the placeholder's edges; the seam comes towards the viewer, so with perspective the halves
    /// overlap a little there and never open a gap onto the background.
    @Test func panelsHangFromThePlaceholderEdgesAndMeetWithoutAGap() {
        let full: CGFloat = 400, half = full / 2
        for current in stride(from: CGFloat(10), through: full, by: 30) {
            let a = FoldPaper.angle(current: current, full: full)
            let top = FoldPaper.panel(top: true, angle: a, full: full), bottom = FoldPaper.panel(top: false, angle: a, full: full)
            // Relative to each anchor (y-up): the top panel's free edge is at -half, the bottom panel's at +half.
            #expect(FoldPaper.project(0, 0, top) == .zero && FoldPaper.project(0, 0, bottom) == .zero)
            let topSeam = FoldPaper.project(0, -half, top), bottomSeam = FoldPaper.project(0, half, bottom)
            // In placeholder coordinates (y-up, 0 at the bottom edge): top hangs from `current`, bottom stands on 0.
            #expect(current + topSeam.y <= bottomSeam.y + 0.001, "gap at current \(current)")
            #expect(topSeam.y <= 0 && bottomSeam.y >= 0)
            #expect(abs(-topSeam.y - current / 2) < current * 0.6 + 1)   // perspective only stretches the halves moderately
        }
        #expect(FoldPaper.shade(top: false, angle: .pi / 2) > FoldPaper.shade(top: true, angle: .pi / 2))
        #expect(FoldPaper.shade(top: true, angle: 0) == 0)
    }
}
