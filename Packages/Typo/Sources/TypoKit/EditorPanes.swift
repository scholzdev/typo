import Foundation
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

extension NSTextContentStorage {
    /// Shows `storage` here. A storage reports its edits to one content storage only, and detaching it from any
    /// content storage drops that link, so one still holding it (another editor pane) lets go first.
    public func adopt(_ storage: NSTextStorage) {
        if let other = storage.textStorageObserver as? NSTextContentStorage, other !== self { other.textStorage = NSTextStorage() }
        textStorage = storage
    }
}
