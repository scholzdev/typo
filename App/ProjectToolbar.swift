import AppKit
import SwiftUI
import TypoKit
import TypstEngine

/// What a "main file › export target" capsule and the export button share: the format a click on Export writes.
enum ExportTarget: String, CaseIterable, Identifiable {
    case pdf, pdfA2b, pdfA3b, pdfUA1, png, svg, archive
    var id: Self { self }

    static let key = "toolbar.exportTarget"

    var title: String {
        switch self {
        case .pdf: "PDF"
        case .pdfA2b: "PDF/A-2b"
        case .pdfA3b: "PDF/A-3b"
        case .pdfUA1: PDFStandard.ua1.title
        case .png: String(localized: "PNG Images")
        case .svg: String(localized: "SVG Images")
        case .archive: String(localized: "Project ZIP")
        }
    }

    var symbol: String {
        switch self {
        case .pdf, .pdfA2b, .pdfA3b, .pdfUA1: "doc.richtext"
        case .png: "photo"
        case .svg: "point.topleft.down.to.point.bottomright.curvepath"
        case .archive: "doc.zipper"
        }
    }

    @MainActor func run(_ project: Project) async {
        switch self {
        case .pdf: await ProjectExporter.pdf(project, .plain)
        case .pdfA2b: await ProjectExporter.pdf(project, .pdfA2b)
        case .pdfA3b: await ProjectExporter.pdf(project, .pdfA3b)
        case .pdfUA1: await ProjectExporter.pdf(project, .ua1)
        case .png: await ProjectExporter.pages(project, .png(ppi: 0))
        case .svg: await ProjectExporter.pages(project, .svg)
        case .archive: await ProjectExporter.archive(project)
        }
    }
}

/// The window toolbar as in Xcode, left to right: navigator and assistant toggles, back and forward, the project's
/// activity view, the "main file › export target" capsule with the issue counter, action buttons, the preview toggle.
struct ProjectToolbar: ToolbarContent {
    let project: Project
    let sidebar: SidebarModel
    let files: FilesController
    let layout: EditorLayout
    let assistant: AssistantModel
    let actions: EditorActions
    let sourceControl: Bool
    @Environment(\.openWindow) private var openWindow
    @AppStorage(ExportTarget.key) private var target = ExportTarget.pdf

    var body: some ToolbarContent {
        if !layout.focus {
            // With the navigator open these two come from its column (ProjectView), which keeps them next to the traffic lights.
            if layout.columns == .detailOnly {
                NavigatorToggles(layout: layout, assistant: assistant, actions: actions)
                ToolbarSpacer(.fixed, placement: .navigation)
            }
            ToolbarItemGroup(placement: .navigation) {
                Button("Go Back", systemImage: "chevron.left") { project.goBack() }
                    .disabled(!project.navigationHistory.canGoBack).help("Go back")
                Button("Go Forward", systemImage: "chevron.right") { project.goForward() }
                    .disabled(!project.navigationHistory.canGoForward).help("Go forward")
            }
            ToolbarSpacer(.fixed, placement: .navigation)
        }
        ToolbarItem(placement: .navigation) {
            ToolbarTitle(project: project, sidebar: sidebar, sourceControl: sourceControl)
        }
        .sharedBackgroundVisibility(.hidden)
        if !layout.focus {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    SchemeCapsule(project: project, target: $target)
                    IssueCounts(project: project) { sidebar.tab = .issues }
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Menu("New", systemImage: "doc.badge.plus") {
                    Button("New File", systemImage: "doc.badge.plus") { files.newFile() }
                    Button("New Folder", systemImage: "folder.badge.plus") { files.newFolder() }
                }
                .help("New file or folder")
                Button("Start Presentation", systemImage: "play.rectangle") { PresentationSession.start(project, presenter: false, openWindow: openWindow) }
                    .disabled(project.preview.pages.isEmpty).help("Show the pages full screen")
                Button("Export \(target.title)", systemImage: "square.and.arrow.up") { Task { await target.run(project) } }
                    .help("Export as \(target.title)")
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle("Preview", systemImage: "rectangle.righthalf.inset.filled", isOn: Binding(get: { layout.showPreview }, set: { layout.showPreview = $0 }))
                    .help("Show or hide the preview")
                Toggle("Inspector", systemImage: "sidebar.trailing", isOn: Binding(get: { layout.showInspector }, set: { layout.showInspector = $0 }))
                    .help("Show or hide the inspector")
            }
        }
    }
}

/// Xcode's two leading buttons: they pick what the sidebar shows, the navigator or the assistant; the editor stays.
/// The button of what is already showing hides the sidebar.
struct NavigatorToggles: ToolbarContent {
    let layout: EditorLayout
    let assistant: AssistantModel
    let actions: EditorActions
    var placement = ToolbarItemPlacement.navigation

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: placement) {
            Toggle("Navigator", systemImage: "list.bullet", isOn: shows(.navigator)).help("Show the navigator")
            Toggle("Assistant", systemImage: "sparkles", isOn: shows(.assistant)).help("Show the assistant")
        }
    }

    private func shows(_ mode: AssistantModel.Mode) -> Binding<Bool> {
        Binding { layout.columns != .detailOnly && assistant.mode == mode } set: { _ in
            let visible = layout.columns != .detailOnly
            if assistant.mode != mode { assistant.toggle(editor: actions) } else if visible { withAnimation { layout.columns = .detailOnly }; return }
            if !visible { withAnimation { layout.columns = .all } }
        }
    }
}

/// Xcode's scheme and destination menus: the previewed (main) document and the export format.
private struct SchemeCapsule: View {
    let project: Project
    @Binding var target: ExportTarget

    var body: some View {
        HStack(spacing: 4) {
            Menu {
                ForEach(Self.typstFiles(project.files), id: \.self) { f in
                    Toggle(f.raw, isOn: Binding(get: { project.main == f }, set: { _ in project.setMain(f) }))
                }
                Divider()
                Toggle("Lock Preview Document", isOn: Binding(get: { project.previewLocked }, set: { project.previewLocked = $0 }))
            } label: {
                Label(project.main.name, systemImage: "doc.text")
            }
            .help("Main document")
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary).accessibilityHidden(true)
            Menu {
                Picker("Export Format", selection: $target) {
                    ForEach(ExportTarget.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label(target.title, systemImage: target.symbol)
            }
            .help("Export format")
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).labelStyle(.titleAndIcon).fixedSize()
        .font(.system(size: 12)).padding(.horizontal, 6)
    }

    private static func typstFiles(_ nodes: [FileNode]) -> [RelPath] {
        nodes.flatMap { $0.isDirectory ? typstFiles($0.children ?? []) : ($0.kind == .typst ? [$0.id] : []) }
    }
}

/// Xcode's activity view without the scheme: app icon, project name and a status line.
private struct ToolbarTitle: View {
    let project: Project
    let sidebar: SidebarModel
    let sourceControl: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 20, height: 20).clipShape(.rect(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 0) {
                Text(project.rootURL.lastPathComponent).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                HStack(spacing: 6) {
                    if let reason = project.saveError {
                        Label("Couldn't save", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).help(reason)
                    } else {
                        CompileStatusBadge(status: project.status)
                    }
                    if sourceControl { GitSyncLabel(project: project, model: sidebar.git) }
                }
                .labelStyle(.titleAndIcon).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Yellow triangle with the warning count, red circle with the error count; opens the Issues navigator.
private struct IssueCounts: View {
    let project: Project
    let open: () -> Void

    var body: some View {
        let all = project.diagnostics
        let errors = all.filter { $0.severity == .error }.count
        let warnings = all.filter { $0.severity == .warning }.count
        HStack(spacing: 6) {
            if errors > 0 { count(errors, "xmark.circle.fill", .red, String(localized: "Errors")) }
            if warnings > 0 { count(warnings, "exclamationmark.triangle.fill", .yellow, String(localized: "Warnings")) }
        }
    }

    private func count(_ n: Int, _ symbol: String, _ color: Color, _ label: String) -> some View {
        Button(action: open) {
            HStack(spacing: 4) { Image(systemName: symbol).foregroundStyle(color); Text("\(n)") }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 3)
        }
        .buttonStyle(.plain).help("Show \(label) in the Issues navigator").accessibilityLabel("\(n) \(label)")
    }
}
