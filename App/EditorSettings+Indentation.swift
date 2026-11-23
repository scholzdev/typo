import AppKit
import TypoKit

extension IndentSettings {
    /// The Indentation settings page's values; unset keys keep the defaults.
    static func fromDefaults(_ d: UserDefaults = .standard) -> IndentSettings {
        var s = IndentSettings.standard
        s.useTabs = d.object(forKey: SettingsKey.indentUseTabs) as? Bool ?? s.useTabs
        s.tabWidth = d.object(forKey: SettingsKey.indentTabWidth) as? Int ?? s.tabWidth
        s.indentWidth = d.object(forKey: SettingsKey.formatIndent) as? Int ?? s.indentWidth
        s.tabKey = (d.string(forKey: SettingsKey.indentTabKey)).flatMap(TabKey.init(rawValue:)) ?? s.tabKey
        s.preferEditorConfig = d.object(forKey: SettingsKey.indentEditorConfig) as? Bool ?? s.preferEditorConfig
        s.indentWhenTyping = d.object(forKey: SettingsKey.indentWhenTyping) as? Bool ?? s.indentWhenTyping
        s.reindentOnPaste = d.object(forKey: SettingsKey.indentOnPaste) as? Bool ?? s.reindentOnPaste
        s.soloBraceIndent = d.object(forKey: SettingsKey.indentSoloBrace) as? Int ?? s.soloBraceIndent
        s.indentComments = d.object(forKey: SettingsKey.indentComments) as? Bool ?? s.indentComments
        s.alignComments = d.object(forKey: SettingsKey.indentAlignComments) as? Bool ?? s.alignComments
        return s
    }
}

extension EditorView.Coordinator {
    // Runs on every defaults change, so it must be idempotent and cheap.
    // shortcut: re-reads the few .editorconfig files on each run (no cache); cache per file if this ever shows in a profile.
    func applyIndentationSettings(_ tv: NSTextView) {
        guard let buffer, let project else { return }
        let root = project.rootURL
        let s = IndentSettings.fromDefaults().resolved(for: root.appendingPathComponent(buffer.path.raw), root: root)
        if buffer.indentSettings != s { buffer.indentSettings = s }
        // Tab characters span `tabWidth` spaces. The empty stops matter: the default style has fixed stops every 28 pt.
        let font = tv.font ?? NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let interval = CGFloat(s.tabWidth) * (" " as NSString).size(withAttributes: [.font: font]).width
        if let p = tv.defaultParagraphStyle, p.defaultTabInterval == interval, p.tabStops.isEmpty { return }
        let p = (tv.defaultParagraphStyle ?? .default).mutableCopy() as! NSMutableParagraphStyle
        p.tabStops = []
        p.defaultTabInterval = interval
        tv.defaultParagraphStyle = p
    }

    /// Re-Indent (⌃I): the selection's lines, or the caret's line, as one undo step.
    func reindent() {
        guard !readOnly, let tv = textView, let r = buffer?.reindent(tv.selectedRange()) else { return }
        selectProgrammatically(r, in: tv)
    }

    /// "Re-indent on paste": pastes `text` shifted to the insertion point's indentation as one undo step.
    /// False when the setting is off or does not apply, so the normal paste runs.
    func pasteReindented(_ text: String) -> Bool {
        guard !readOnly, let tv = textView else { return false }
        let sel = tv.selectedRange()
        guard let new = buffer?.reindentedPaste(text, replacing: sel) else { return false }
        replace(sel, with: new, selecting: NSRange(location: sel.location + (new as NSString).length, length: 0))
        return true
    }
}
