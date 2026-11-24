import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit

@Suite struct PresentationClockTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1000)

    @Test func countsOnlyWhileRunning() {
        var c = PresentationClock()
        #expect(c.elapsed(at: t0) == 0 && c.isUntouched)
        c.start(at: t0)
        #expect(c.elapsed(at: t0 + 10) == 10)
        c.pause(at: t0 + 10)
        #expect(c.elapsed(at: t0 + 100) == 10 && !c.isRunning && !c.isUntouched)
        c.toggle(at: t0 + 100)
        #expect(c.elapsed(at: t0 + 105) == 15)
    }

    @Test func startTwiceKeepsTheFirstStart() {
        var c = PresentationClock()
        c.start(at: t0)
        c.start(at: t0 + 5)
        #expect(c.elapsed(at: t0 + 10) == 10)
    }

    @Test func resetStopsAndZeroes() {
        var c = PresentationClock()
        c.start(at: t0)
        c.reset()
        #expect(c.isUntouched && c.elapsed(at: t0 + 50) == 0)
    }

    @Test func readsOutElapsedAndRemaining() {
        var c = PresentationClock()
        c.start(at: t0)
        #expect(c.readout(at: t0 + 3725.9) == "01:02:05")
        #expect(c.readout(at: t0 + 50, remainingOf: 120) == "00:01:10")
        #expect(c.readout(at: t0 + 125, remainingOf: 120) == "-00:00:05")
    }

    @Test func parsesDurations() {
        #expect(PresentationClock.seconds(from: "20") == 1200)
        #expect(PresentationClock.seconds(from: " 5:30 ") == 330)
        #expect(PresentationClock.seconds(from: "1:02:03") == 3723)
        for bad in ["", "a", "5:60", "-1", "1:2:3:4", "5:"] { #expect(PresentationClock.seconds(from: bad) == nil) }
        #expect(PresentationClock.minutesSeconds(4530) == "75:30")
    }
}

@Suite struct PresentationSlideShowTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1000)

    @Test func movesClampToThePages() {
        var s = SlideShow(page: 3)
        #expect(s.current(count: 12) == 3)
        s.move(by: 100, count: 12, at: t0)
        #expect(s.current(count: 12) == 11)
        s.move(by: -100, count: 12, at: t0)
        #expect(s.current(count: 12) == 0)
        s.go(to: .max, count: 12, at: t0)
        #expect(s.current(count: 12) == 11)
    }

    @Test func shrinkingDocumentClampsTheCurrentPage() {
        let s = SlideShow(page: 9)
        #expect(s.current(count: 4) == 3)
        #expect(s.current(count: 0) == 0)
        #expect(SlideShow(page: -2).current(count: 4) == 0)
    }

    @Test func firstMoveStartsTheClock() {
        var s = SlideShow()
        s.move(by: -1, count: 5, at: t0)    // stays on page 0: no move, no clock
        #expect(s.clock.isUntouched)
        s.move(by: 1, count: 5, at: t0)
        #expect(s.clock.isRunning)
        #expect(s.clock.elapsed(at: t0 + 3) == 3)
    }

    @Test func movingDoesNotRestartAPausedClock() {
        var s = SlideShow()
        s.move(by: 1, count: 5, at: t0)
        s.clock.pause(at: t0 + 4)
        s.move(by: 1, count: 5, at: t0 + 10)
        #expect(!s.clock.isRunning && s.clock.elapsed(at: t0 + 20) == 4)
    }
}
