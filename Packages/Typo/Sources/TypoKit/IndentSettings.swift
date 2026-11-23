import Foundation

/// How the editor indents one file: the app's Indentation settings, possibly overridden by `.editorconfig`.
/// The app assigns it to `Buffer.indentSettings`; core functions take it as a parameter.
public struct IndentSettings: Equatable, Sendable {
    public enum TabKey: String, Sendable, CaseIterable {
        /// Tab nests in leading whitespace, list items and multi-line selections; elsewhere it types a tab.
        case leadingWhitespace
        /// Tab nests the current line or selection wherever the caret is.
        case always
        /// Tab types one unit at the caret; only a multi-line selection is nested.
        case insertsTab
    }

    public var useTabs = false
    /// Columns a tab character spans on screen.
    public var tabWidth = 4
    /// Columns of one level when indenting with spaces; with tabs one level is one tab.
    public var indentWidth = 2
    public var tabKey = TabKey.leadingWhitespace
    public var preferEditorConfig = true
    public var indentWhenTyping = true
    public var reindentOnPaste = false
    /// Extra columns Re-Indent gives a line that holds only an opening bracket.
    public var soloBraceIndent = 0
    public var indentComments = true
    public var alignComments = false
    /// True when `.editorconfig` set `indent_style`: the file's style then beats a line's own tabs or spaces.
    public var explicitStyle = false

    public static let standard = IndentSettings()
    public init() {}

    /// One level for a line indented by `indent`. The line's own style wins (a tab-indented line keeps tabs, a
    /// space-indented one gets spaces) so mixed files stay consistent per line; an unindented line follows the
    /// preference. Only `.editorconfig`'s `indent_style` is explicit enough to override a line's style.
    public func unit(for indent: String) -> String {
        let tabs = explicitStyle || indent.isEmpty ? useTabs : indent.hasPrefix("\t")
        return tabs ? "\t" : String(repeating: " ", count: indentWidth)
    }

    /// Columns of one level.
    var levelWidth: Int { useTabs ? tabWidth : indentWidth }

    /// Display columns of a run of blanks (tabs advance to the next tab stop).
    func columns(_ blanks: some StringProtocol) -> Int {
        blanks.reduce(0) { col, c in c == "\t" ? (col / tabWidth + 1) * tabWidth : col + 1 }
    }

    /// Blanks spanning `columns`, in the preferred style.
    func blanks(_ columns: Int) -> String {
        let n = max(columns, 0)
        guard useTabs else { return String(repeating: " ", count: n) }
        return String(repeating: "\t", count: n / tabWidth) + String(repeating: " ", count: n % tabWidth)
    }
}
