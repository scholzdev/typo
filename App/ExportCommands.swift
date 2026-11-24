import AppKit
import SwiftUI
import TypoKit
import UniformTypeIdentifiers
import PDFKit
import TypstEngine

/// File ▸ Export: PDF, PDF/A, and one PNG or SVG file per page.
struct ExportCommands: Commands {
    let recents: RecentProjects
    private let focus = FocusedCommandContext()

    private var context: AppCommandContext { focus.context(recents: recents) }

    var body: some Commands {
        let ctx = context
        CommandGroup(replacing: .printItem) {
            AppCommands.items(AppCommands.print(ctx))
        }
        CommandGroup(after: .newItem) {
            Menu {
                AppCommands.items(AppCommands.export(ctx))
            } label: { Label("Export", systemImage: "square.and.arrow.up") }
            .disabled(ctx.project == nil)
        }
    }
}

@MainActor enum ProjectExporter {
    /// Warns about fonts the engine could not find; false when the user cancels.
    private static func confirmFonts(_ project: Project, printing: Bool) -> Bool {
        let names = QuickFixes.missingFonts(in: project.diagnostics)
        guard !names.isEmpty else { return true }
        let list = ListFormatter.localizedString(byJoining: names)
        let detail: LocalizedStringResource = switch (names.count == 1, printing) {
        case (true, true): "\(list) isn\u{2019}t installed, so the document uses a replacement font. Install it or choose other fonts, then print again."
        case (true, false): "\(list) isn\u{2019}t installed, so the document uses a replacement font. Install it or choose other fonts, then export again."
        case (false, true): "\(list) aren\u{2019}t installed, so the document uses a replacement font. Install them or choose other fonts, then print again."
        case (false, false): "\(list) aren\u{2019}t installed, so the document uses a replacement font. Install them or choose other fonts, then export again."
        }
        return confirm("Some Fonts Are Missing", detail, ok: printing ? "Print Anyway" : "Export Anyway")
    }

    static func print(_ project: Project) async {
        guard confirmFonts(project, printing: true) else { return }
        do {
            let data = try await project.exportPDF(standard: .plain)
            guard let document = PDFDocument(data: data),
                  let op = document.printOperation(for: NSPrintInfo.shared, scalingMode: .pageScaleToFit, autoRotate: true) else {
                return showAlert("Could Not Print", "The document could not be prepared for printing.")
            }
            op.showsPrintPanel = true
            op.showsProgressPanel = true
            op.jobTitle = (project.pdfFileName as NSString).deletingPathExtension
            if let window = NSApp.keyWindow { op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil) } else { op.run() }
        } catch {
            showAlert("Could Not Print", error)
        }
    }

    /// The export dialog, preset to `target`, then the save panel for what was chosen.
    static func export(_ project: Project, _ target: ExportTarget) async {
        do {
            let count = try await project.exportPageCount()
            guard let choice = await chooseExport(project, target: target, pageCount: count) else { return }
            switch choice.target {
            case .archive: await archive(project)
            case .png, .svg:
                guard confirmFonts(project, printing: false) else { return }
                try await pages(project, choice.target == .png ? .png(ppi: choice.ppi) : .svg, choice.pages, count: count)
            case .pdf, .pdfA2b, .pdfA3b, .pdfUA1:
                guard confirmFonts(project, printing: false), let standard = choice.target.standard else { return }
                try await pdf(project, standard, choice.pages.spans(pageCount: count))
            }
        } catch {
            showExportFailure(error, pdfUA: target == .pdfUA1)
        }
    }

    private static func pdf(_ project: Project, _ standard: PDFStandard, _ spans: [PageSpan]?) async throws {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = project.pdfFileName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try await project.exportPDF(standard: standard, pages: spans).write(to: url)
    }

    private static func archive(_ project: Project) async {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = (project.pdfFileName as NSString).deletingPathExtension + ".zip"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try await project.exportArchive(to: url) } catch { showExportFailure(error) }
    }

    /// One file per chosen page, named after its page number. One page: a save panel. Several: a folder (the sandbox grants no siblings of a saved file).
    private static func pages(_ project: Project, _ format: PageFormat, _ selection: PageSelection, count: Int) async throws {
        let numbers = (selection.spans(pageCount: count) ?? [PageSpan(first: 1, last: count)])
            .flatMap { ($0.first ?? 1)...($0.last ?? count) }
        let ext = format == .svg ? "svg" : "png"
        let stem = (project.pdfFileName as NSString).deletingPathExtension
        let panel: NSSavePanel
        if numbers.count == 1 {
            panel = NSSavePanel()
            panel.allowedContentTypes = [format == .svg ? .svg : .png]
            panel.nameFieldStringValue = count == 1 ? "\(stem).\(ext)" : "\(stem)-\(numbers[0]).\(ext)"
        } else {
            let open = NSOpenPanel()
            open.canChooseFiles = false
            open.canChooseDirectories = true
            open.canCreateDirectories = true
            open.prompt = String(localized: "Export")
            open.message = String(localized: "Choose a folder for \(numbers.count) \(ext.uppercased()) files.")
            panel = open
        }
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        let width = String(count).count
        let urls = numbers.count == 1 ? [chosen] : numbers.map {
            chosen.appending(path: "\(stem)-\(String(format: "%0\(width)d", $0)).\(ext)")
        }
        if numbers.count > 1, urls.contains(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            guard confirm("Replace Existing Files?", "Some files named \u{201C}\(stem)-…\(".\(ext)")\u{201D} already exist in this folder.", ok: "Replace") else { return }
        }
        let data = try await project.exportPages(format)
        guard data.count == count else { throw ProjectError.exportFailed(String(localized: "The document changed while exporting. Try again.")) }
        for (n, url) in zip(numbers, urls) { try data[n - 1].write(to: url, options: .atomic) }
    }
}
