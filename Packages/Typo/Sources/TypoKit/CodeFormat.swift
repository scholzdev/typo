import Foundation
import TypstEngine

/// typstyle formatting as a minimal replacement.
public enum CodeFormat {
    /// The edit that formats `text` (or the nodes around `range`, UTF-16); nil if unchanged, on syntax errors or failure.
    public static func edit(_ text: String, range: NSRange? = nil, width: Int = 80, indent: Int = 2) -> Replacement? {
        // Whole lines: typstyle formats the smallest node around the range, and a caret alone covers just a name.
        let lines = range.map { r -> NSRange in
            let ns = text as NSString
            var l = ns.lineRange(for: r)
            while l.length > 0, [10, 13].contains(ns.character(at: NSMaxRange(l) - 1)) { l.length -= 1 }
            return l
        }
        guard let f = Bridge.format(text, range: lines, width: width, indent: indent) else { return nil }
        let old = Array((text as NSString).substring(with: f.range).utf16), new = Array(f.text.utf16)
        var head = 0
        while head < min(old.count, new.count), old[head] == new[head] { head += 1 }
        var tail = 0
        while tail < min(old.count, new.count) - head, old[old.count - 1 - tail] == new[new.count - 1 - tail] { tail += 1 }
        // Don't split a surrogate pair.
        func isLow(_ u: UInt16) -> Bool { (0xDC00...0xDFFF).contains(u) }
        if head > 0, head < new.count, isLow(new[head]) { head -= 1 }
        if tail > 0, tail < new.count, isLow(new[new.count - tail]) { tail -= 1 }
        guard head + tail < old.count || head + tail < new.count else { return nil }
        let text = String(decoding: new[head..<(new.count - tail)], as: UTF16.self)
        return Replacement(range: NSRange(location: f.range.location + head, length: old.count - head - tail), text: text)
    }
}

extension Buffer {
    public func codeFormatEdit(selection: NSRange?, width: Int, indent: Int) -> Replacement? {
        isTypst ? CodeFormat.edit(storage.string, range: selection, width: width, indent: indent) : nil
    }
}

extension Project {
    /// Formats each unsaved Typst buffer as one undo step (Format on Save).
    public func formatDirtyBuffers(width: Int, indent: Int) { prepareDirtyBuffersForSave(format: (width, indent), trimBlankLines: nil) }

    /// The edits an explicit save makes to each unsaved buffer, formatting then trimming, as one undo step per buffer.
    /// `trimBlankLines` nil leaves whitespace alone; false trims content lines; true also empties blank lines.
    public func prepareDirtyBuffersForSave(format: (width: Int, indent: Int)?, trimBlankLines: Bool?) {
        for b in buffers.values where b.isDirty {
            b.undoManager.beginUndoGrouping()
            defer { b.undoManager.endUndoGrouping() }
            if let f = format, let r = b.codeFormatEdit(selection: nil, width: f.width, indent: f.indent) { b.apply([r], actionName: "Format Document") }
            if let blank = trimBlankLines {
                let text = b.storage.string
                b.apply(WhitespaceTrim.edits(in: text, tokens: b.isTypst ? TypstSyntax.tokens(in: text) : [], blankLines: blank),
                        actionName: format == nil ? "Trim Whitespace" : nil)
            }
        }
    }
}
