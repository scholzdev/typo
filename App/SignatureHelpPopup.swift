import AppKit
import TypoKit
import TypstEngine

/// Signature help: while the caret is in a call's argument list, the callee's parameters above the caret line,
/// the one the current argument fills in bold, with the first paragraph of its documentation underneath.
/// Non-activating like the completion list, which it sits above.
@MainActor final class SignatureHelpPopup {
    private static let maxWidth: CGFloat = 560
    private static let inset: CGFloat = 8
    private let panel = GlassChildPanel(cornerRadius: 10)
    private let label = NSTextField(labelWithString: "")
    private(set) var shown: SignatureHelp?

    var isVisible: Bool { panel.isVisible }

    init() {
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.isSelectable = false
        panel.content.addSubview(label)
    }

    /// Shows `help` above the caret of `textView` (below it near the screen top).
    func show(_ help: SignatureHelp, in textView: NSTextView) {
        guard let window = textView.window else { return }
        shown = help
        let text = Self.content(help)
        label.attributedStringValue = text
        let bounds = text.boundingRect(with: NSSize(width: Self.maxWidth - 2 * Self.inset, height: .greatestFiniteMagnitude),
                                       options: [.usesLineFragmentOrigin, .usesFontLeading])
        let textSize = NSSize(width: ceil(bounds.width) + 4, height: ceil(bounds.height) + 2)
        label.frame = NSRect(origin: NSPoint(x: Self.inset, y: Self.inset), size: textSize)
        let size = NSSize(width: textSize.width + 2 * Self.inset, height: textSize.height + 2 * Self.inset)
        let caret = textView.firstRect(forCharacterRange: NSRange(location: textView.selectedRange().location, length: 0), actualRange: nil)
        panel.show(size: size, x: caret.minX - Self.inset - 20, belowY: caret.minY, aboveY: caret.maxY, in: window,
                   appearance: textView.effectiveAppearance, preferAbove: true)
    }

    func hide() {
        shown = nil
        panel.hide()
    }

    /// `name(a, b: int, ..rest)` with the active parameter bold, then its documentation's first paragraph.
    private static func content(_ help: SignatureHelp) -> NSAttributedString {
        let size = Highlighter.fontSize - 1
        let mono = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        let bold = NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
        let out = NSMutableAttributedString()
        func add(_ s: String, _ font: NSFont = mono, _ color: NSColor = .secondaryLabelColor) {
            out.append(NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color]))
        }
        add(help.name, mono, .systemBlue)
        add("(")
        for (i, p) in help.params.enumerated() {
            if i > 0 { add(", ") }
            if i == help.active { add(p.label, bold, .labelColor) } else { add(p.label) }
        }
        add(")")
        if let docs = help.activeParameter?.docs, let summary = summary(docs) {
            out.append(NSAttributedString(string: "\n" + summary, attributes: [
                .font: NSFont.systemFont(ofSize: size - 1), .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        }
        return out
    }

    /// The first paragraph of Markdown docs, without backticks and capped, nil when empty.
    private static func summary(_ docs: String) -> String? {
        guard let first = docs.components(separatedBy: "\n\n").first?.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "`", with: "").trimmingCharacters(in: .whitespaces), !first.isEmpty else { return nil }
        return first.count > 240 ? String(first.prefix(240)) + "…" : first
    }
}

extension EditorView.Coordinator {
    static let signatureTriggers: Set<Character> = ["(", ","]

    /// Asks for signature help at the caret; the reply shows the popup, or hides it outside a call. Only the newest
    /// request is shown.
    func requestSignatureHelp() {
        guard let tv = textView, let project, let file = buffer?.path, buffer?.isTypst == true else { return hideSignatureHelp() }
        let sel = tv.selectedRange()
        guard sel.length == 0 else { return hideSignatureHelp() }
        signatureRequestID += 1
        let id = signatureRequestID
        Task { [weak self] in
            let help = await project.signatureHelp(in: file, at: sel.location)
            guard let self, id == self.signatureRequestID, self.buffer?.path == file, let tv = self.textView else { return }
            guard let help, tv.selectedRange() == sel else { return self.hideSignatureHelp() }
            self.signaturePopup.show(help, in: tv)
        }
    }

    func hideSignatureHelp() {
        signatureRequestID += 1                          // a reply still in flight must not reopen it
        signaturePopup.hide()
    }

    /// `(` and `,` open signature help; while it shows, every typed character and caret move updates it.
    func signatureHelpTyped(_ ch: Character) {
        if (Self.signatureTriggers.contains(ch) && CompletionPreferences.signaturesWhileTyping) || signaturePopup.isVisible { requestSignatureHelp() }
    }

    func signatureHelpCaretMoved() {
        if signaturePopup.isVisible { requestSignatureHelp() }
    }
}
