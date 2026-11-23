import SwiftUI
import TypoKit

extension SettingsKey {
    static let defaultEncoding = "defaultTextEncoding"
    static let defaultLineEnding = "defaultLineEnding"
    static let convertFilesOnSave = "convertFilesOnSave"
    static let trimTrailingWhitespace = "trimTrailingWhitespace"
    static let trimBlankLines = "trimWhitespaceOnlyLines"
}

extension TextEncoding {
    var title: String {
        switch self {
        case .utf8: "Unicode (UTF-8)"
        case .latin1: "Western (ISO Latin 1)"
        case .windows1252: "Western (Windows-1252)"
        case .macRoman: "Western (Mac OS Roman)"
        case .utf16: "Unicode (UTF-16)"
        }
    }
}

extension LineEnding {
    var title: String {
        switch self {
        case .lf: "macOS / Unix (LF)"
        case .crlf: "Windows (CRLF)"
        case .cr: "Classic Mac OS (CR)"
        }
    }
}

enum FilePreferences {
    /// The file settings as the project reads them at every open, reload and save.
    static func current() -> TextFileSettings {
        let d = UserDefaults.standard
        return TextFileSettings(fallback: (d.string(forKey: SettingsKey.defaultEncoding)).flatMap(TextEncoding.init) ?? .utf8,
                                lineEnding: (d.string(forKey: SettingsKey.defaultLineEnding)).flatMap(LineEnding.init) ?? .lf,
                                convertOnSave: d.bool(forKey: SettingsKey.convertFilesOnSave))
    }

    /// nil: leave whitespace alone; false: trim content lines; true: empty blank lines too.
    static func trimBlankLines() -> Bool? {
        let d = UserDefaults.standard
        guard d.object(forKey: SettingsKey.trimTrailingWhitespace) as? Bool ?? true else { return nil }
        return d.object(forKey: SettingsKey.trimBlankLines) as? Bool ?? true
    }
}

/// The file-handling and whitespace rows of the Text Editing page.
struct TextEditingFileSections: View {
    @AppStorage(SettingsKey.defaultEncoding) private var encoding = TextEncoding.utf8
    @AppStorage(SettingsKey.defaultLineEnding) private var lineEnding = LineEnding.lf
    @AppStorage(SettingsKey.convertFilesOnSave) private var convert = false
    @AppStorage(SettingsKey.trimTrailingWhitespace) private var trim = true
    @AppStorage(SettingsKey.trimBlankLines) private var trimBlank = true

    var body: some View {
        Section {
            Picker("Default text encoding", selection: $encoding) {
                ForEach(TextEncoding.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Text("Typst reads UTF-8. Other files open with this encoding and are saved back in it unless converted.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Default line endings", selection: $lineEnding) {
                ForEach([LineEnding.lf, .crlf], id: \.self) { Text($0.title).tag($0) }
            }
            Toggle("Convert existing files on save", isOn: $convert)
        }
        Section("When Editing") {
            Toggle("Automatically trim trailing whitespace", isOn: $trim)
            Toggle("Trim whitespace-only lines", isOn: $trimBlank).disabled(!trim)
            Text("Applies when you save with ⌘S. Autosave never changes your text.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
