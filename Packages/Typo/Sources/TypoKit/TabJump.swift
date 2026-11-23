import Foundation
import TypstEngine

/// Tab / Shift-Tab between the arguments of the call around the caret.
enum TabJump {
    /// The selection Tab (forward) or Shift-Tab should produce, nil for the normal key behaviour.
    static func selection(in text: String, syntax: SyntaxMirror, from sel: NSRange, forward: Bool) -> NSRange? {
        let ns = text as NSString
        guard sel.location <= ns.length else { return nil }
        // Indentation and list items keep Tab for nesting; so does a multi-line selection.
        if Indent.shifts(ns, sel) { return nil }
        var pos = sel.location
        var previous: NSRange?
        // An enclosing list is tried at the end (forward) or start (backward) of the one just left.
        while let (whole, targets) = syntax.args(at: pos, minTargets: 2), whole != previous {
            let cur = targets.lastIndex { $0.location <= pos } ?? -1
            if forward, cur + 1 < targets.count { return targets[cur + 1] }
            if !forward, cur >= 1 { return targets[cur - 1] }
            previous = whole
            pos = forward ? NSMaxRange(whole) : whole.location
        }
        return forward ? previous.map { NSRange(location: NSMaxRange($0), length: 0) } : nil
    }
}
