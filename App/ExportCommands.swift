import AppKit
import SwiftUI
import TypoKit
import UniformTypeIdentifiers
import TypstEngine

/// File ▸ Export: PDF, PDF/A, and one PNG or SVG file per page.
struct ExportCommands: Commands {
    let recents: RecentProjects
    private let focus = FocusedCommandContext()

    private var context: AppCommandContext { focus.context(recents: recents) }

    var body: some Commands {
        let ctx = context
        CommandGroup(after: .newItem) {
            Menu {
                AppCommands.items(AppCommands.export(ctx))
            } label: { Label("Export", systemImage: "square.and.arrow.up") }
            .disabled(ctx.project == nil)
        }
    }
}

@MainActor enum ProjectExporter {
    static func pdf(_ project: Project, _ standard: PDFStandard) async {
        do {
            let pdf = try await project.exportPDF(standard: standard)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = project.pdfFileName
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try pdf.write(to: url)
        } catch {
            showExportFailure(error, pdfUA: standard == .ua1)
        }
    }

    static func archive(_ project: Project) async {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = (project.pdfFileName as NSString).deletingPathExtension + ".zip"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try await project.exportArchive(to: url) } catch { showExportFailure(error) }
    }

    /// `.png`'s ppi is chosen in the panel. One page: a save panel. Several: a folder (the sandbox grants no siblings of a saved file).
    static func pages(_ project: Project, _ requested: PageFormat) async {
        do {
            let count = try await project.exportPageCount()
            let isPNG = requested != .svg
            let ext = isPNG ? "png" : "svg"
            let stem = (project.pdfFileName as NSString).deletingPathExtension
            let accessory = isPNG ? PPIAccessory() : nil
            let panel: NSSavePanel
            if count == 1 {
                panel = NSSavePanel()
                panel.allowedContentTypes = [isPNG ? .png : .svg]
                panel.nameFieldStringValue = "\(stem).\(ext)"
            } else {
                let open = NSOpenPanel()
                open.canChooseFiles = false
                open.canChooseDirectories = true
                open.canCreateDirectories = true
                open.prompt = "Export"
                open.message = "Choose a folder for \(count) \(ext.uppercased()) files."
                panel = open
            }
            panel.accessoryView = accessory?.view
            guard panel.runModal() == .OK, let chosen = panel.url else { return }
            let format: PageFormat = accessory.map { .png(ppi: $0.ppi) } ?? .svg
            let width = String(count).count
            let urls = count == 1 ? [chosen] : (1...count).map {
                chosen.appending(path: "\(stem)-\(String(format: "%0\(width)d", $0)).\(ext)")
            }
            if count > 1, urls.contains(where: { FileManager.default.fileExists(atPath: $0.path) }) {
                guard confirm("Replace Existing Files?", "Some files named \u{201C}\(stem)-…\(".\(ext)")\u{201D} already exist in this folder.", ok: "Replace") else { return }
            }
            let data = try await project.exportPages(format)
            guard data.count == urls.count else { throw ProjectError.exportFailed("The document changed while exporting. Try again.") }
            for (d, url) in zip(data, urls) { try d.write(to: url, options: .atomic) }
        } catch {
            showExportFailure(error)
        }
    }
}

/// "Resolution: 300 ppi" under the panel's file list.
@MainActor private final class PPIAccessory {
    static let choices = [72, 150, 300, 600]
    private let popup = NSPopUpButton(frame: .zero, pullsDown: false)
    let view: NSView

    init() {
        popup.addItems(withTitles: Self.choices.map { "\($0) ppi" })
        popup.selectItem(at: 2)
        let stack = NSStackView(views: [NSTextField(labelWithString: "Resolution:"), popup])
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        view = stack
    }

    var ppi: Int { Self.choices[popup.indexOfSelectedItem] }
}
