import CoreGraphics
import Foundation

/// Why the preview is being synced to the editor's caret.
public enum SyncReason: Sendable {
    case navigation       // selection changed with no edit: click, arrows, Cmd-arrows
    case typing           // the selection moved because of an edit
    case resync           // a new document arrived; the caret's text may sit elsewhere now
    case programmatic     // reveal, click-to-jump, completion accept, undo/redo
}

public struct SyncDecision: Equatable, Sendable {
    public let request: Bool              // ask the engine at all
    public let scrollIfOutside: Bool      // scroll when the target is outside the visible rect
    public let marker: Bool               // show the short-lived marker
}

/// The trigger policy. `userScrolled` is true if the user scrolled the preview by hand since the last
/// navigation sync; only a navigation overrides that.
public func syncDecision(_ reason: SyncReason, userScrolled: Bool) -> SyncDecision {
    switch reason {
    case .navigation: SyncDecision(request: true, scrollIfOutside: true, marker: true)
    case .typing, .resync: SyncDecision(request: true, scrollIfOutside: !userScrolled, marker: false)
    case .programmatic: SyncDecision(request: false, scrollIfOutside: false, marker: false)
    }
}
