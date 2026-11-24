import AppKit
import SwiftUI

/// A plain-text Markdown editor that styles as you write: bigger bold headings, **bold**, *italic*, `code` and list
/// markers. The text stays plain Markdown; only its look changes.
struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    var editable = true
    /// Set by the view: wraps the selection or prefixes its lines, for the format buttons.
    var actions: Binding<MarkdownActions?>? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        tv.isRichText = false
        tv.allowsUndo = true
        tv.isEditable = editable
        // The agent reads these characters as written: no curly quotes or long dashes.
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.textContainerInset = NSSize(width: 20, height: 16)   // the same column as the card above
        tv.font = MarkdownStyle.body
        tv.typingAttributes = MarkdownStyle.base
        tv.delegate = context.coordinator
        tv.string = text
        context.coordinator.restyle(tv)
        tv.setAccessibilityLabel(String(localized: "Workflow text"))
        scroll.drawsBackground = false
        tv.drawsBackground = false
        context.coordinator.textView = tv
        DispatchQueue.main.async { actions?.wrappedValue = MarkdownActions(textView: tv) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? NSTextView else { return }
        tv.isEditable = editable
        if tv.string != text { tv.string = text; context.coordinator.restyle(tv) }
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextView
        weak var textView: NSTextView?
        init(_ parent: MarkdownTextView) { self.parent = parent }

        func textDidChange(_ note: Notification) {
            guard let tv = note.object as? NSTextView else { return }
            restyle(tv)
            parent.text = tv.string
        }

        func restyle(_ tv: NSTextView) {
            guard let storage = tv.textStorage else { return }
            storage.beginEditing()
            MarkdownStyle.apply(to: storage)
            storage.endEditing()
            tv.typingAttributes = MarkdownStyle.base   // text typed after a heading is not a heading
        }
    }
}

/// The format buttons' edits on the editor's selection; they go through the text view so Undo works.
@MainActor struct MarkdownActions {
    weak var textView: NSTextView?

    /// Puts `mark` around the selection, or inserts two of them with the caret between.
    func wrap(_ mark: String) {
        guard let tv = textView else { return }
        let r = tv.selectedRange()
        let inner = (tv.string as NSString).substring(with: r)
        replace(r, with: mark + inner + mark, select: NSRange(location: r.location + mark.count, length: inner.utf16.count))
    }

    /// Starts each selected line with `prefix`, or removes it when every line has it.
    func prefixLines(_ prefix: String) {
        guard let tv = textView else { return }
        let ns = tv.string as NSString
        let r = ns.lineRange(for: tv.selectedRange())
        var lines = ns.substring(with: r).components(separatedBy: "\n")
        let trailing = lines.last == "" ? lines.removeLast() : nil
        let all = lines.allSatisfy { $0.hasPrefix(prefix) }
        lines = lines.map { line in
            if all { return String(line.dropFirst(prefix.count)) }
            // A heading button replaces the level a line already has.
            let rest = prefix.hasPrefix("#") ? String(line.drop { $0 == "#" }.drop { $0 == " " }) : line
            return prefix + rest
        }
        let out = lines.joined(separator: "\n") + (trailing != nil ? "\n" : "")
        replace(r, with: out, select: NSRange(location: r.location + out.utf16.count - (trailing != nil ? 1 : 0), length: 0))
    }

    private func replace(_ r: NSRange, with s: String, select: NSRange) {
        guard let tv = textView, tv.shouldChangeText(in: r, replacementString: s) else { return }
        tv.replaceCharacters(in: r, with: s)
        tv.didChangeText()
        tv.setSelectedRange(select)
        tv.window?.makeFirstResponder(tv)
    }
}

/// The light Markdown styling of `MarkdownTextView`.
@MainActor enum MarkdownStyle {
    static let body = NSFont.systemFont(ofSize: 14)
    static let paragraph: NSParagraphStyle = {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 3
        p.paragraphSpacing = 4
        return p
    }()
    static let base: [NSAttributedString.Key: Any] = [.font: body, .foregroundColor: NSColor.textColor, .paragraphStyle: paragraph]

    // Line rules first, then inline ones; later matches win where they overlap.
    private static let heading = try! NSRegularExpression(pattern: "^(#{1,6})[ \\t]+.*$", options: .anchorsMatchLines)
    private static let list = try! NSRegularExpression(pattern: "^([ \\t]*)([-*+]|\\d+[.)])[ \\t]+.*$", options: .anchorsMatchLines)
    private static let quote = try! NSRegularExpression(pattern: "^>.*$", options: .anchorsMatchLines)
    private static let bold = try! NSRegularExpression(pattern: "(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1")
    private static let italic = try! NSRegularExpression(pattern: "(?<![*_\\w])([*_])(?=\\S)(.+?)(?<=\\S)\\1(?![*_\\w])")
    private static let code = try! NSRegularExpression(pattern: "`[^`\\n]+`")
    private static let fence = try! NSRegularExpression(pattern: "^```.*?^```[^\\n]*$", options: [.anchorsMatchLines, .dotMatchesLineSeparators])

    /// Less space above a heading than a gap between paragraphs would suggest, a little more below.
    private static func heading(_ level: Int) -> NSParagraphStyle {
        let p = paragraph.mutableCopy() as! NSMutableParagraphStyle
        p.paragraphSpacingBefore = level == 1 ? 2 : 6
        p.paragraphSpacing = 6
        return p
    }

    static func apply(to s: NSTextStorage) {
        let all = NSRange(location: 0, length: s.length)
        let text = s.string
        s.setAttributes(base, range: all)
        let marker = NSColor.quaternaryLabelColor
        for m in heading.matches(in: text, range: all) {
            let level = m.range(at: 1).length
            let size: CGFloat = level == 1 ? 22 : level == 2 ? 17 : 15
            s.addAttribute(.font, value: NSFont.systemFont(ofSize: size, weight: .bold), range: m.range)
            s.addAttribute(.foregroundColor, value: marker, range: m.range(at: 1))
            s.addAttribute(.paragraphStyle, value: heading(level), range: m.range)
        }
        for m in list.matches(in: text, range: all) {
            // A hanging indent: wrapped lines start under the text, not under the dash.
            let lead = (text as NSString).substring(with: m.range(at: 1)) + (text as NSString).substring(with: m.range(at: 2)) + " "
            let p = paragraph.mutableCopy() as! NSMutableParagraphStyle
            p.headIndent = (lead as NSString).size(withAttributes: [.font: body]).width
            s.addAttribute(.paragraphStyle, value: p, range: m.range)
            s.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: m.range(at: 2))
        }
        for m in quote.matches(in: text, range: all) { s.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: m.range) }
        for m in bold.matches(in: text, range: all) {
            s.applyFontTraits(.boldFontMask, range: m.range)
            dim(s, m, marker)
        }
        for m in italic.matches(in: text, range: all) {
            s.applyFontTraits(.italicFontMask, range: m.range)
            dim(s, m, marker)
        }
        let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        for m in code.matches(in: text, range: all) + fence.matches(in: text, range: all) {
            s.addAttribute(.font, value: mono, range: m.range)
            s.addAttribute(.backgroundColor, value: NSColor.labelColor.withAlphaComponent(0.05), range: m.range)
        }
        for m in code.matches(in: text, range: all) {
            s.addAttribute(.foregroundColor, value: marker, range: NSRange(location: m.range.location, length: 1))
            s.addAttribute(.foregroundColor, value: marker, range: NSRange(location: NSMaxRange(m.range) - 1, length: 1))
        }
    }

    /// Greys the `**` or `*` around a match.
    private static func dim(_ s: NSTextStorage, _ m: NSTextCheckingResult, _ color: NSColor) {
        let mark = m.range(at: 1).length
        s.addAttribute(.foregroundColor, value: color, range: NSRange(location: m.range.location, length: mark))
        s.addAttribute(.foregroundColor, value: color, range: NSRange(location: NSMaxRange(m.range) - mark, length: mark))
    }
}
