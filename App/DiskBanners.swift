import AppKit
import SwiftUI
import TypoKit

private struct FileBanner: View {
    let message: LocalizedStringKey
    let secondary: LocalizedStringKey
    let primary: LocalizedStringKey
    let onSecondary: () -> Void
    let onPrimary: () -> Void

    var body: some View {
        HStack {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
            Spacer()
            Button(secondary, action: onSecondary)
                .buttonStyle(.glass)
            Button(primary, action: onPrimary)   // a failure shows as "Couldn't save"
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .padding(.horizontal, 8).padding(.top, 8)
    }
}

/// Above the editor while the shown file has unsaved text and also changed on disk. Saves skip it until a choice.
struct ChangedOnDiskBanner: View {
    let project: Project
    let buffer: Buffer

    var body: some View {
        if buffer.isChangedOnDisk {
            FileBanner(message: "\u{201C}\(buffer.path.name)\u{201D} was changed on disk.", secondary: "Use Disk Version", primary: "Keep Mine",
                       onSecondary: { Task { await project.useDisk(buffer.path) } },
                       onPrimary: { Task { try? await project.keepMine(buffer.path) } })
        }
    }
}

/// Quit and window close: unsaved text of a file changed on disk is neither overwritten nor dropped without asking.
@MainActor func confirmChangedFiles(_ project: Project) async {
    for path in project.changedOnDisk.sorted(by: { $0.raw < $1.raw }) where project.buffer(for: path)?.isDirty == true {
        if confirm("\u{201C}\(path.name)\u{201D} was changed on disk.", "It also has unsaved changes. Keep yours and overwrite the disk version?", ok: "Keep Mine", cancel: "Use Disk Version") {
            try? await project.keepMine(path)
        } else { await project.useDisk(path) }
    }
}

/// Above the editor while the shown file is gone from disk. Saves skip it until "Save Again"; "Close" drops it.
struct MissingFileBanner: View {
    let project: Project
    let buffer: Buffer

    var body: some View {
        if buffer.isMissingOnDisk {
            FileBanner(message: "\u{201C}\(buffer.path.name)\u{201D} was deleted outside Typo.", secondary: "Close", primary: "Save Again",
                       onSecondary: { project.closeMissing(buffer.path) },
                       onPrimary: { Task { try? await project.saveAgain(buffer.path) } })
        }
    }
}

/// Quit and window close: unsaved text of a file deleted outside the app is neither written back nor dropped
/// without asking.
@MainActor func confirmMissingFiles(_ project: Project) async {
    for path in project.unsavedMissingFiles() {
        if confirm("\u{201C}\(path.name)\u{201D} was deleted outside Typo.", "It has unsaved changes. Save it again to keep them?", ok: "Save Again", cancel: "Don\u{2019}t Save") {
            try? await project.saveAgain(path)
        }
    }
}
