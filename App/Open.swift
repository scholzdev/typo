import AppKit
import SwiftUI
import TypoKit
import UniformTypeIdentifiers
import TypstEngine

extension UTType {
    static let typstSource = UTType(exportedAs: "me.florianscholz.typo.typst-source", conformingTo: .plainText)
}

@MainActor func showAlert(_ title: LocalizedStringResource, _ detail: LocalizedStringResource) {
    showAlert(title, verbatim: String(localized: detail))
}

/// For details that are already text: an error's description, a diagnostic from Typst.
@MainActor func showAlert(_ title: LocalizedStringResource, verbatim detail: String) {
    let a = NSAlert()
    a.messageText = String(localized: title)
    a.informativeText = detail
    a.runModal()
}

@MainActor func showAlert(_ title: LocalizedStringResource, _ error: any Error) {
    showAlert(title, verbatim: error.localizedDescription)
}

@MainActor func confirm(_ title: LocalizedStringResource, _ detail: LocalizedStringResource, ok: LocalizedStringResource, cancel: LocalizedStringResource = "Cancel", style: NSAlert.Style = .warning) -> Bool {
    confirm(title, verbatim: String(localized: detail), ok: ok, cancel: cancel, style: style)
}

@MainActor func confirm(_ title: LocalizedStringResource, verbatim detail: String, ok: LocalizedStringResource, cancel: LocalizedStringResource = "Cancel", style: NSAlert.Style = .warning) -> Bool {
    let a = NSAlert()
    a.alertStyle = style
    a.messageText = String(localized: title)
    a.informativeText = detail
    a.addButton(withTitle: String(localized: ok))
    a.addButton(withTitle: String(localized: cancel))
    return a.runModal() == .alertFirstButtonReturn
}

/// The only place that turns a picked folder or .typ file into a window.
@MainActor struct ProjectOpener {
    let recents: RecentProjects
    let openWindow: OpenWindowAction

    @discardableResult func choose(files: Bool = true, folders: Bool = true) -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = files
        panel.canChooseDirectories = folders
        if files {
            // Another installed app (e.g. Typst itself) may own `.typ` under its own UTI, so `.typ` files never
            // conform to ours; accept every type registered for the extension. Folders must be listed explicitly
            // once a content-type filter is set, or they're greyed out too.
            let typ = UTType.types(tag: "typ", tagClass: .filenameExtension, conformingTo: nil)
            panel.allowedContentTypes = [.typstSource] + typ + (folders ? [.folder] : [])
        }
        panel.message = folders && files ? String(localized: "Choose a Typst project folder or a .typ file")
            : folders ? String(localized: "Choose a Typst project folder") : String(localized: "Choose a .typ file")
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return open(url)
    }

    @discardableResult func open(_ url: URL) -> Bool {
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let root: URL
        let main: RelPath
        if isDir {
            root = url
            let typs = ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).filter { $0.hasSuffix(".typ") }.sorted()
            guard let first = typs.contains("main.typ") ? "main.typ" : typs.first, let rel = RelPath(first) else {
                showAlert("No Typst File", "\"\(url.lastPathComponent)\" contains no .typ file at its top level.")
                return false
            }
            main = rel
        } else {
            // A picked file grants only that file in the sandbox, so ask for its folder too. Declined: the
            // parent is still the root and sibling imports fail as ordinary diagnostics.
            let parent = url.deletingLastPathComponent()
            let granted = askForFolder(containing: url)
            let prefix = (granted?.standardizedFileURL.path ?? parent.path) + "/"
            if url.standardizedFileURL.path.hasPrefix(prefix), let rel = RelPath(String(url.standardizedFileURL.path.dropFirst(prefix.count))) {
                root = granted ?? parent
                main = rel
            } else {
                root = parent
                main = RelPath(url.lastPathComponent)!
            }
        }
        do { openWindow(value: try recents.register(root: root, main: main)) } catch {
            showAlert("Could Not Open \"\(root.lastPathComponent)\"", error)
            return false
        }
        return true
    }

    private func askForFolder(containing file: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.directoryURL = file.deletingLastPathComponent()
        panel.prompt = String(localized: "Grant Access")
        panel.message = String(localized: "To resolve imports and images next to \"\(file.lastPathComponent)\", Typo needs access to its folder.")
        return panel.runModal() == .OK ? panel.url : nil
    }
}
