import SwiftUI
import TypoKit

enum TextEditingPage: String, Hashable, CaseIterable {
    case display, completion, indentation

    var title: String {
        switch self {
        case .display: String(localized: "Display")
        case .completion: String(localized: "Completion")
        case .indentation: String(localized: "Indentation")
        }
    }

    var symbol: String {
        switch self {
        case .display: "inset.filled.trailingthird.rectangle"    // Xcode's own symbols for these pages
        case .completion: "characters.lowercase"
        case .indentation: "arrow.right.to.line.compact"
        }
    }

    var color: Color {
        switch self {
        case .display: .blue
        case .completion: .orange
        case .indentation: .green
        }
    }
}

struct TextEditingSettings: View {
    @Environment(SettingsNavigation.self) private var nav
    @AppStorage(SettingsKey.hoverJumpHint) private var hoverJumpHint = true
    @AppStorage(SettingsKey.lintHints) private var lintHints = true
    @AppStorage(SettingsKey.formatOnSave) private var formatOnSave = false
    @AppStorage(SettingsKey.vimMode) private var vimMode = false
    @AppStorage(SettingsKey.relativeNumbers) private var relativeNumbers = RelativeNumbers.off.rawValue
    @ObservedObject private var shortcuts = ShortcutStore.shared

    // No NavigationStack: a push would cover the window's header and its Back button.
    var body: some View {
        switch nav.page.flatMap({ $0.tab == .textEditing ? TextEditingPage(rawValue: $0.id) : nil }) {
        case .display: TextEditingDisplaySettings()
        case .completion: TextEditingCompletionSettings()
        case .indentation: TextEditingIndentationSettings()
        case nil: main
        }
    }

    private var main: some View {
        Form {
            Section {
                ForEach(TextEditingPage.allCases, id: \.self) { page in
                    Button {
                        nav.page = SettingsSubpage(tab: .textEditing, id: page.rawValue, title: page.title)
                    } label: {
                        HStack {
                            Label {
                                Text(page.title)
                            } icon: {
                                Image(systemName: page.symbol)
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(page.color, in: RoundedRectangle(cornerRadius: 5))
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            TextEditingFileSections()
            Section("Editing") {
                Toggle("Show the shortcut in hover cards", isOn: $hoverJumpHint)
                Toggle("Show lint hints", isOn: $lintHints)
                Toggle("Vim mode", isOn: $vimMode)
                Text("Modal editing in the editor: Esc for Normal mode, i to insert, v for Visual mode, : for w, q and wq. Also in View > Vim Mode.").font(.caption).foregroundStyle(.secondary)
                if vimMode {
                    Picker("Relative line numbers", selection: $relativeNumbers) {
                        Text("Off").tag(RelativeNumbers.off.rawValue)
                        Text("Relative").tag(RelativeNumbers.relative.rawValue)
                        Text("Hybrid").tag(RelativeNumbers.hybrid.rawValue)
                    }
                    Text("Counts lines from the caret line, folded ones included. Hybrid keeps the caret line's own number. Also :set rnu, :set nornu and :set nu rnu.").font(.caption).foregroundStyle(.secondary)
                    if shortcuts.sets.isDefault {
                        Button("Use the Vim shortcut set") { shortcuts.change { $0.select(ShortcutSets.vimName) } }
                        Text(ShortcutSets.vimDescription).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Formatting") {
                Toggle("Format on Save (⌘S)", isOn: $formatOnSave)
                Text("Formatting uses typstyle with the line width from Display and the indent width from Indentation. Autosave never formats.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .pane()
    }
}
