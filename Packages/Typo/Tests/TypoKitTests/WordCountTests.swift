import CoreGraphics
import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit

@Suite struct WordCountTests {
    // MARK: Selection

    @Test func selectionCountsOnlyTheProsePartsInside() {
        let text = "one two three four five six"
        let ns = text as NSString
        let prose = [ns.range(of: "one two"), ns.range(of: "five six")]
        let all = NSRange(location: 0, length: ns.length)
        #expect(WordCount.selected(in: text, prose: prose, selection: all) == 4)
        #expect(WordCount.selected(in: text, prose: prose, selection: ns.range(of: "two three four five")) == 2)
        #expect(WordCount.selected(in: text, prose: prose, selection: ns.range(of: "three")) == 0)
        #expect(WordCount.selected(in: text, prose: prose, selection: NSRange(location: 2, length: 0)) == 0)
        #expect(WordCount.selected(in: text, prose: [], selection: all) == 0)
    }

    @Test func staleProseRangesPastTheTextAreIgnored() {
        let text = "short text"
        let prose = [NSRange(location: 0, length: 5), NSRange(location: 6, length: 40)]
        #expect(WordCount.selected(in: text, prose: prose, selection: NSRange(location: 0, length: 100)) == 1)
    }

    // MARK: Label

    @Test func labelPluralizesAndFormats() {
        let en = Locale(identifier: "en_US")
        #expect(WordCount.label(total: 1, selected: 1, locale: en) == "1 of 1 word")
        #expect(WordCount.label(total: 2, selected: 0, locale: en) == "0 of 2 words")
        #expect(WordCount.label(total: 1, goal: 500, locale: en) == "1 / 500 words")
        #expect(WordCount.label(total: 1_234_567, locale: Locale(identifier: "de_DE")) == "1.234.567 words")
    }

    // MARK: Preview arithmetic

    @Test func percentAndZoomAreInverse() {
        #expect(PreviewMath.percent(zoom: 1, fitWidth: 595, pageWidth: 595) == 100)
        #expect(PreviewMath.percent(zoom: 1, fitWidth: 892.5, pageWidth: 595) == 150)
        #expect(PreviewMath.percent(zoom: 2, fitWidth: 0, pageWidth: 0) == 100)
        for p in PreviewMath.presets {
            let z = PreviewMath.zoom(percent: p, fitWidth: 700, pageWidth: 595)
            #expect(PreviewMath.percent(zoom: z, fitWidth: 700, pageWidth: 595) == p)
        }
        #expect(PreviewMath.zoom(percent: 100, fitWidth: 0, pageWidth: 595) == 1)
    }

    @Test func zoomIsClamped() {
        #expect(PreviewMath.zoom(percent: 1, fitWidth: 700, pageWidth: 595) == PreviewMath.zoomRange.lowerBound)
        #expect(PreviewMath.zoom(percent: 10_000, fitWidth: 700, pageWidth: 595) == PreviewMath.zoomRange.upperBound)
    }

    @Test func framesStackPagesWithTheirAspect() {
        let f = PreviewMath.frames(sizes: [CGSize(width: 100, height: 200), CGSize(width: 200, height: 100), .zero], width: 50, inset: 10)
        #expect(f == [CGRect(x: 10, y: 10, width: 50, height: 100), CGRect(x: 10, y: 120, width: 50, height: 25), CGRect(x: 10, y: 155, width: 50, height: 0)])
    }

    @Test func mostVisiblePageHasTheLargestArea() {
        let f = [CGRect(x: 0, y: 0, width: 10, height: 100), CGRect(x: 0, y: 110, width: 10, height: 100)]
        #expect(PreviewMath.mostVisiblePage(frames: f, visible: CGRect(x: 0, y: 50, width: 10, height: 100)) == 0)   // 50 vs 40
        #expect(PreviewMath.mostVisiblePage(frames: f, visible: CGRect(x: 0, y: 90, width: 10, height: 100)) == 1)   // 10 vs 80
        #expect(PreviewMath.mostVisiblePage(frames: f, visible: CGRect(x: 0, y: 0, width: 10, height: 210)) == 0)    // tie: the first
        #expect(PreviewMath.mostVisiblePage(frames: f, visible: CGRect(x: 0, y: 500, width: 10, height: 10)) == nil)
        #expect(PreviewMath.mostVisiblePage(frames: [], visible: .zero) == nil)
    }
}
