import SwiftUI

extension SettingsKey {
    static let completeWhileTyping = "completeWhileTyping"
    static let signatureWhileTyping = "signatureWhileTyping"
    static let autoPairBrackets = "autoPairBrackets"
    static let completionAcceptKeys = "completionAcceptKeys"
}

enum AcceptKeys: String, CaseIterable {
    case both, returnOnly, tabOnly

    var title: String {
        switch self {
        case .both: "Return and Tab"
        case .returnOnly: "Return only"
        case .tabOnly: "Tab only"
        }
    }
}

/// The completion settings, read where a key press or a typed character is decided.
enum CompletionPreferences {
    private static func flag(_ key: String) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
    static var suggestWhileTyping: Bool { flag(SettingsKey.completeWhileTyping) }
    static var signaturesWhileTyping: Bool { flag(SettingsKey.signatureWhileTyping) }
    static var autoPair: Bool { flag(SettingsKey.autoPairBrackets) }
    static var acceptKeys: AcceptKeys { UserDefaults.standard.string(forKey: SettingsKey.completionAcceptKeys).flatMap(AcceptKeys.init) ?? .both }
}

struct TextEditingCompletionSettings: View {
    @AppStorage(SettingsKey.completeWhileTyping) private var suggest = true
    @AppStorage(SettingsKey.signatureWhileTyping) private var signatures = true
    @AppStorage(SettingsKey.autoPairBrackets) private var autoPair = true
    @AppStorage(SettingsKey.completionAcceptKeys) private var accept = AcceptKeys.both

    var body: some View {
        Form {
            Section {
                Toggle("Suggest completions while typing", isOn: $suggest)
                Text("F5 and ⌥Esc always request completions.").font(.caption).foregroundStyle(.secondary)
                Toggle("Show function signatures while typing", isOn: $signatures)
                Toggle("Automatically insert closing brackets and quotes", isOn: $autoPair)
                Picker("Accept completions with", selection: $accept) {
                    ForEach(AcceptKeys.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
        }
        .pane()
    }
}
