import CoreGraphics
import Foundation

/// One heading of the last successfully compiled document. `offset` is UTF-16 in `file`'s text.
public struct OutlineItem: Identifiable, Sendable, Equatable {
    public let id: Int
    public let level: Int
    public let numbering: String       // plain numbering text ("1.2."), empty when unnumbered
    public let title: String
    public let page: Int               // 0-based
    public let y: CGFloat              // pt from the page top
    public let file: RelPath
    public let offset: Int

    public func with(offset: Int) -> OutlineItem {
        OutlineItem(id: id, level: level, numbering: numbering, title: title, page: page, y: y, file: file, offset: offset)
    }
}
