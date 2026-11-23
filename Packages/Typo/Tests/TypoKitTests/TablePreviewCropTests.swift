import CoreGraphics
import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit

@Suite struct TablePreviewCropTests {
    /// Page (top-down y): a paragraph, the table, its caption close below, then an image after a block gap.
    @Test func cropKeepsTableAndCaptionButNotTheTextAround() throws {
        let w = 400, h = 400
        let ctx = try #require(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
        ctx.setFillColor(gray: 1, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(gray: 0, alpha: 1)
        func box(_ x: Int, _ top: Int, _ width: Int, _ height: Int) {   // CG's origin is bottom-left
            ctx.fill(CGRect(x: x, y: h - top - height, width: width, height: height))
        }
        box(20, 40, 360, 10)      // paragraph above
        box(100, 80, 200, 60)     // table
        box(150, 146, 100, 8)     // caption, 6 px below
        box(120, 180, 160, 50)    // image, 26 px below the caption
        let image = try #require(ctx.makeImage())
        let r = try #require(TablePreviewer.inkBounds(image, seed: CGRect(x: 110, y: 90, width: 120, height: 30), scale: 1))
        #expect(r == CGRect(x: 100, y: 80, width: 200, height: 74))
    }

    /// Bold header cells must seed the crop too, or a header set apart by whitespace is cut off.
    @Test func boldHeaderCellsSeedTheCrop() {
        let text = "table(table.header([*AI Model*], [_Year_]), [GPT], [$2023$])"
        let offsets = TablePreviewer.textOffsets(in: text, range: NSRange(location: 0, length: (text as NSString).length))
        let starts = offsets.map { (text as NSString).substring(with: NSRange(location: $0 - 1, length: 2)) }
        #expect(starts == ["AI", "Ye", "GP"])
    }
}
