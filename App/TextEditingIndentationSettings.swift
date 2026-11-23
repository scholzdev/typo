import SwiftUI
import TypoKit

extension SettingsKey {
    static let indentUseTabs = "indentUseTabs"
    static let indentTabWidth = "indentTabWidth"
    // Indent width is `formatIndent`: one value for typing, Tab, Re-Indent and the typstyle formatter.
    static let indentTabKey = "indentTabKey"
    static let indentEditorConfig = "indentPreferEditorConfig"
    static let indentWhenTyping = "indentWhenTyping"
    static let indentOnPaste = "indentReindentOnPaste"
    static let indentSoloBrace = "indentSoloBrace"
    static let indentComments = "indentComments"
    static let indentAlignComments = "indentAlignComments"
}

struct TextEditingIndentationSettings: View {
    @AppStorage(SettingsKey.indentUseTabs) private var useTabs = false
    @AppStorage(SettingsKey.indentTabWidth) private var tabWidth = 4
    @AppStorage(SettingsKey.formatIndent) private var indentWidth = 2
    @AppStorage(SettingsKey.indentTabKey) private var tabKey = IndentSettings.TabKey.leadingWhitespace
    @AppStorage(SettingsKey.indentEditorConfig) private var editorConfig = true
    @AppStorage(SettingsKey.indentWhenTyping) private var whenTyping = true
    @AppStorage(SettingsKey.indentOnPaste) private var onPaste = false
    @AppStorage(SettingsKey.indentSoloBrace) private var soloBrace = 0
    @AppStorage(SettingsKey.indentComments) private var comments = true
    @AppStorage(SettingsKey.indentAlignComments) private var alignComments = false

    var body: some View {
        Form {
            Section {
                Picker("Prefer to indent using", selection: $useTabs) {
                    Text("Spaces").tag(false)
                    Text("Tabs").tag(true)
                }
                Text("Format Document uses typstyle, which only writes spaces: with Tabs it turns indentation back into spaces.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Tab width") { Stepper("\(tabWidth) spaces", value: $tabWidth, in: 1...16).monospacedDigit().accessibilityLabel("Tab width") }
                LabeledContent("Indent width") { Stepper("\(indentWidth) spaces", value: $indentWidth, in: 1...16).monospacedDigit().accessibilityLabel("Indent width") }
                Text("With Tabs, one level is one tab. Indent width sets the spaces of a level and the formatter's indentation.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Tab key", selection: $tabKey) {
                    Text("Indents in leading whitespace").tag(IndentSettings.TabKey.leadingWhitespace)
                    Text("Indents always").tag(IndentSettings.TabKey.always)
                    Text("Inserts tab").tag(IndentSettings.TabKey.insertsTab)
                }
                Toggle("Prefer settings from .editorconfig files", isOn: $editorConfig)
                Text("Uses indent_style, indent_size and tab_width from .editorconfig files in the project folder for the files they match.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Syntax-Aware Indentation") {
                Toggle("Indent when typing", isOn: $whenTyping)
                Toggle("Re-indent on paste", isOn: $onPaste)
                Picker("Indent solo { by", selection: $soloBrace) {
                    Text("Don’t Indent").tag(0)
                    Text("2 spaces").tag(2)
                    Text("4 spaces").tag(4)
                    Text("8 spaces").tag(8)
                }
                Toggle("Indent // comments", isOn: $comments)
                Toggle("Align consecutive // comments", isOn: $alignComments)
                Text("Re-Indent (⌃I) applies the bracket depth and these options to the selection or the current line.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .pane()
    }
}
