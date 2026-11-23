import Foundation
import TypstEngine

extension FileNode {
    public var kind: FileKind { FileKind(path: id.raw, isDirectory: isDirectory) }

    /// Every non-directory below, depth first.
    var leaves: [RelPath] { isDirectory ? (children ?? []).flatMap(\.leaves) : [id] }
}
