import CoreGraphics
import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit

@Suite struct PreviewMathTests {
    let a4 = CGSize(width: 595, height: 842)

    @Test func fitWidthIsZoomOne() {
        #expect(PreviewMath.zoom(fitting: .width, page: a4, viewport: CGSize(width: 800, height: 400), fitWidth: 752) == 1)
    }

    @Test func fitPageIsLimitedByHeight() {
        // A short, wide viewport: the page's height decides.
        let z = PreviewMath.zoom(fitting: .page, page: a4, viewport: CGSize(width: 800, height: 600), fitWidth: 752, inset: 16)
        let width = 752 * z
        #expect(abs(width * 842 / 595 - (600 - 32)) < 0.01)
    }

    @Test func fitPageNeverExceedsTheColumn() {
        // A tall, narrow viewport: Fit Page equals Fit Width.
        #expect(PreviewMath.zoom(fitting: .page, page: a4, viewport: CGSize(width: 300, height: 2000), fitWidth: 252) == 1)
    }

    @Test func twoPagesFitSideBySide() {
        let z = PreviewMath.zoom(fitting: .twoPages, page: a4, viewport: CGSize(width: 800, height: 4000), fitWidth: 752, inset: 16)
        #expect(abs(2 * 752 * z + 16 - 752) < 0.01)
    }

    @Test func fitWithoutViewportFallsBackToWidth() {
        #expect(PreviewMath.zoom(fitting: .page, page: a4, viewport: .zero, fitWidth: 752) == 1)
        #expect(PreviewMath.zoom(fitting: .page, page: .zero, viewport: CGSize(width: 1, height: 1), fitWidth: 752) == 1)
    }

    @Test func framesInOneColumnStack() {
        let f = PreviewMath.frames(sizes: [a4, a4], width: 100, inset: 10)
        #expect(f.count == 2)
        #expect(f[0].minX == 10 && f[0].minY == 10)
        #expect(f[1].minX == 10 && abs(f[1].minY - (10 + 100 * 842 / 595 + 10)) < 0.001)
    }

    @Test func framesInTwoColumnsShareARow() {
        let tall = CGSize(width: 595, height: 1190)
        let f = PreviewMath.frames(sizes: [a4, tall, a4], width: 100, inset: 10, columns: 2)
        #expect(f[0].minY == f[1].minY)
        #expect(f[1].minX == 120)
        #expect(f[2].minX == 10)
        #expect(abs(f[2].minY - (10 + 200 + 10)) < 0.001)         // the row is as tall as its tallest page
    }

    @Test func rowsGroupPages() {
        #expect(PreviewMath.rows(count: 5, columns: 2) == [0..<2, 2..<4, 4..<5])
        #expect(PreviewMath.rows(count: 2, columns: 1) == [0..<1, 1..<2])
        #expect(PreviewMath.rows(count: 0, columns: 2).isEmpty)
    }
}

@MainActor @Suite struct PreviewModelTests {
    @Test func failedCompileKeepsLastGoodRenderAndMarksItStale() async throws {
        let (p, _) = try await TestEnv.project("proj-a")
        _ = await p.settle()
        let good = p.preview.pages
        #expect(!good.isEmpty && !p.preview.isStale)

        let b = try #require(p.selectedBuffer)
        type(b, "\n#let x = (")
        _ = await p.settle()
        #expect(p.preview.pages.map(\.hash) == good.map(\.hash))
        #expect(p.preview.isStale)

        replace(b, NSRange(location: b.storage.length - 11, length: 11), with: "")
        _ = await p.settle()
        #expect(!p.preview.isStale)
    }

    @Test func manualZoomLeavesTheFitModeAndKeepsColumns() async throws {
        let (p, _) = try await TestEnv.project("proj-a")
        _ = await p.settle()
        let m = p.preview
        m.fitWidth = 752
        m.viewport = CGSize(width: 800, height: 600)
        m.fit = .twoPages
        #expect(m.columns == 2 && m.zoom < 0.5)
        m.zoom(by: 1.25)
        #expect(m.fit == nil && m.columns == 2)
        m.fit = .page
        #expect(m.columns == 1)
        let fitted = m.zoom
        m.viewport = CGSize(width: 800, height: 900)
        #expect(m.zoom > fitted)                                      // a fit follows the viewport
        m.set(zoom: 100)
        #expect(m.zoom == PreviewMath.zoomRange.upperBound)
    }

    @Test func thumbnailRenderIsNotTheStaleFallback() async throws {
        let (p, _) = try await TestEnv.project("proj-a")
        _ = await p.settle()
        let a = try #require(p.preview.pages.first)
        let thumb = ImageKey(a.hash, pixelsPerPoint: 0.25)
        await p.preview.render(a, thumb, thumbnail: true)
        #expect(p.preview.image(for: thumb) != nil)
        #expect(p.preview.image(for: ImageKey(a.hash, pixelsPerPoint: 2), index: 0) == nil)
    }
}
