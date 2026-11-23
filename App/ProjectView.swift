import AppKit
import SwiftUI
import TypoKit
import TypstEngine

struct ProjectView: View {
    @Bindable var project: Project
    @State private var tables = TableEditing()
    @State private var sidebar: SidebarModel
    @State private var actions = EditorActions()
    @State private var layout = EditorLayout()
    @State private var files: FilesController
    @State private var palette = LibraryPanel()
    @State private var quickOpen = QuickOpenPanel()
    @State private var assistant: AssistantModel
    @Environment(RecentProjects.self) private var recents
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage(SettingsKey.sourceControl) private var sourceControl = true
    @AppStorage(SettingsKey.lintHints) private var lintHints = true
    @AppStorage(SettingsKey.compileWhileTyping) private var compileWhileTyping = true
    @AppStorage(SettingsKey.accessibilityChecks) private var accessibilityChecks = AccessibilityChecks.whenUA.rawValue
    @AppStorage(ExportTarget.key) private var exportTarget = ExportTarget.pdf

    init(project: Project) {
        self.project = project
        let model = SidebarModel()
        _sidebar = State(initialValue: model)
        _files = State(initialValue: FilesController(project: project, model: model))
        _assistant = State(initialValue: AssistantModel(project: project))
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $layout.columns) {
            // One container with one width: the two contents must not resize the column (and with it the editor) when they swap.
            ZStack {
                if assistant.mode == .assistant { AssistantSidebar(model: assistant) } else { SidebarView(project: project, model: sidebar, files: files) }
            }
            // The navigator's system tab strip can't shrink below ~260 pt; a narrower column centred it and cut off every tab's left edge.
            .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .navigationSplitViewColumnWidth(min: 300, ideal: 300, max: 440)
                .toolbar(removing: .sidebarToggle)
                .toolbar { if !layout.focus, layout.columns != .detailOnly { NavigatorToggles(layout: layout, assistant: assistant, actions: actions, placement: .automatic) } }
        } detail: {
            // Two panes in one detail column, so the preview can leave the window (pop-out) without rebuilding the editor.
            SplitPanes(autosaveName: "Tympan.split.\(project.id.raw)", showsTrailing: !project.preview.isPoppedOut && !layout.focus && layout.showPreview,
                       leading: EditorPane(project: project, sidebar: sidebar, tables: tables, actions: actions, layout: layout),
                       trailing: PreviewPane(project: project, popOut: popOut))
            .inspector(isPresented: Binding(get: { layout.showInspector && layout.inspectorFits && !layout.focus },
                                            set: { if !layout.focus, layout.inspectorFits { layout.showInspector = $0 } })) {
                InspectorView(project: project, sidebar: sidebar, actions: actions, tables: tables, browseFonts: { layout.library = .fonts })
            }
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { layout.collapseInspector(forWidth: $0) }
        .onChange(of: project.selectionRequests) { sidebar.quickLook = nil }
        .onChange(of: lintHints, initial: true) { project.lintEnabled = lintHints }
        .onChange(of: AccessibilityChecks.enabled(accessibilityChecks, target: exportTarget), initial: true) { project.accessibilityChecks = $1 }
        .onChange(of: compileWhileTyping, initial: true) { project.compilesWhileTyping = compileWhileTyping }
        .onChange(of: project.fileRevision) { sidebar.searchOutcome = nil }      // hits may name files that moved; the search tab reruns
        .onAppear {
            files.startWatching()
            actions.explainSelection = { [assistant, actions] in assistant.explainSelection(editor: actions) }
            project.navigation = .current
            project.showInSecondPane = { [layout] f, permanent in
                layout.secondFile = f
                if permanent { layout.tabs.makePermanent(f) }
            }
        }
        .fileHistory(files)
        .onDisappear {
            files.stopWatching()
            assistant.closeAgents()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in files.filesChanged() }
        .focusedSceneValue(\.files, files)
        .modifier(ProjectTitle(project: project, sidebar: sidebar))
        .focusedSceneValue(\.tables, tables)
        .focusedSceneValue(\.editorActions, actions)
        .citationPicker(project: project, actions: actions, tables: tables)
        .focusedSceneValue(\.editorLayout, layout)
        .focusedSceneValue(\.sidebar, sidebar)
        .focusedSceneValue(\.assistant, assistant)
        .sheet(isPresented: Binding(get: { tables.editing != nil }, set: { if !$0 { tables.editing = nil } })) {
            if let model = tables.editing {
                TableEditorView(model: model, done: tables.apply, cancel: { tables.editing = nil }, completion: {
                    let c = await project.cellCompletion(for: tables.editor?.buffer?.path)
                    tables.completion = c
                    return c
                }, complete: { model, row, column, text, caret, request, fallback in
                    guard let buffer = tables.editor?.buffer else { return fallback.items(for: request) }
                    return await project.completeCell(model, row: row, column: column, text: text, caret: caret, request: request,
                                                      in: buffer.path, buffer: buffer.storage.string, fallback: fallback)
                }, renderCells: { model, fill, size in
                    guard let buffer = tables.editor?.buffer else { return [:] }
                    if tables.previewer == nil { tables.previewer = project.tablePreviewer() }
                    let text = buffer.storage.string
                    // The file with the table as edited, so references inside it resolve against the current cells.
                    let spliced = TableCode.edit(model, in: text).map { (text as NSString).replacingCharacters(in: $0.range, with: $0.replacement) } ?? text
                    let cells = (model.header ?? []).map(\.text) + model.rows.flatMap { $0.map(\.text) }
                    return await tables.previewer?.renderCells(cells, file: buffer.path, text: spliced, overlays: project.openTexts, fill: fill, size: size) ?? [:]
                }, preview: { model in
                    guard let buffer = tables.editor?.buffer else { return nil }
                    if tables.previewer == nil { tables.previewer = project.tablePreviewer() }
                    let text = buffer.storage.string
                    let ns = text as NSString
                    // The document with the table as edited, and where the table (or its figure) now sits.
                    let (spliced, range) = TableCode.edit(model, in: text).map {
                        (ns.replacingCharacters(in: $0.range, with: $0.replacement), NSRange(location: $0.range.location, length: ($0.replacement as NSString).length))
                    } ?? (text, model.range)
                    return await tables.previewer?.render(file: buffer.path, text: spliced, range: range, overlays: project.openTexts,
                                                          pixelsPerPoint: TableEditorView.previewPixelsPerPoint)
                })
            }
        }
        .alert("This Table Can’t Be Edited Visually",
               isPresented: Binding(get: { tables.unsupportedReason != nil }, set: { if !$0 { tables.unsupportedReason = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(tables.unsupportedReason ?? "").textSelection(.enabled)
        }
        .onChange(of: layout.library) { _, kind in setLibrary(kind) }
        .onChange(of: layout.quickOpen) { _, mode in setQuickOpen(mode) }
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ProjectToolbar(project: project, sidebar: sidebar, files: files, layout: layout, assistant: assistant, actions: actions, sourceControl: sourceControl)
        }
    }
}

extension ProjectView {
    /// Shows the library panel for this window on `kind`, switches its tab when open, or closes it for nil; commands are computed at show time for fresh enabled states.
    fileprivate func setLibrary(_ kind: LibraryKind?) {
        guard let kind else { return palette.close() }
        if palette.isOpen { return palette.setKind(kind) }
        guard let parent = NSApp.keyWindow else { layout.library = nil; return }
        let commands = AppCommands.all(AppCommandContext(project: project, tables: tables, editor: actions, files: files, fileListFocused: false,
                                                         layout: layout, recents: recents, openWindow: openWindow, sidebar: sidebar, assistant: assistant))
        palette.show(kind, commands: commands, project: project, editor: actions, over: parent, onKind: { layout.library = $0 }, onClose: { layout.library = nil })
    }

    /// Shows Open Quickly or Go to Line over this window, or closes it for nil.
    fileprivate func setQuickOpen(_ mode: QuickOpenMode?) {
        guard let mode else { return quickOpen.close() }
        guard let parent = NSApp.keyWindow else { layout.quickOpen = nil; return }
        let model = QuickOpenModel(mode: mode)
        model.goToLine = { [actions] in actions.goToLine($0) }
        let recents = QuickOpenRecents(project.id)
        model.open = { [project, layout] result, alternate in
            recents.record(result.item)
            openQuickly(result, alternate: alternate, in: parent, project: project, layout: layout)
        }
        if mode == .files {
            model.recent = recents.load()
            model.openFiles = ([project.selectedFile].compactMap { $0 } + project.tabs.paths.reversed()).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
            model.forgetRecents = { recents.clear() }
            Task { model.items = await project.quickOpenItems() }
        }
        quickOpen.show(model, projectName: project.rootURL.lastPathComponent, over: parent) { layout.quickOpen = nil }
    }

    fileprivate func popOut() {
        let id = PopOutID(project: project.id)
        if project.preview.isPoppedOut { dismissWindow(value: id) } else { openWindow(value: id) }
    }
}

/// The window title and the selection's side effects. A modifier of its own: it reads `selectedFile` in its own body,
/// so a tab switch re-evaluates only this, not `ProjectView` and with it both split panes' root views.
private struct ProjectTitle: ViewModifier {
    let project: Project
    let sidebar: SidebarModel

    func body(content: Content) -> some View {
        content
            .onChange(of: project.selectedFile) { sidebar.quickLook = nil }
            .navigationTitle(sidebar.quickLook?.raw ?? project.selectedFile?.raw ?? project.main.raw)
    }
}

struct EditorPane: View {
    @AppStorage(SettingsKey.inlineIssues) private var inlineIssues = true
    let project: Project
    let sidebar: SidebarModel
    let tables: TableEditing
    let actions: EditorActions
    let layout: EditorLayout
    /// The last shown buffer: kept on screen while the next file is still opening, so the editor is not torn down
    /// and rebuilt for the moment `selectedBuffer` is nil.
    @State private var held: Buffer?

    /// The selected buffer, or while it opens the previous one.
    private var shownBuffer: Buffer? {
        if let b = project.selectedBuffer { return b }
        guard let f = project.selectedFile, project.isOpening(f) else { return nil }
        return held
    }

    var body: some View {
        let showsBar = (sidebar.quickLook == nil && shownBuffer != nil && !showsBibForm) || (layout.split && !layout.focus)
        let bottomBar = EditorBottomBar(project: project, actions: actions, tables: tables, sidebar: sidebar, layout: layout)
        let panes = SplitPanes(autosaveName: "Tympan.editorSplit.\(project.id.raw)", showsTrailing: layout.split && !layout.focus,
                               leading: leading, trailing: SecondEditorPane(project: project, tables: tables, actions: actions, layout: layout))
        panes.safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if showsBar { bottomBar }
                if layout.bottom.isShown { BottomArea(project: project, model: layout.bottom) }
            }
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { layout.bottom.available = $0 }
        .onChange(of: project.selectedFile) { old, new in layout.firstFileChanged(from: old, to: new); sidebar.quickLook = nil }
        .onChange(of: project.selectedBuffer, initial: true) { _, b in if let b { held = b } }
    }

    /// A `.bib` file shows the entry form unless the window switched to its source.
    private var showsBibForm: Bool {
        sidebar.quickLook == nil && !layout.bibSource && shownBuffer.map { BibTeX.isFormEditable($0.path.raw) } == true
    }

    /// The tab bar sits above the pane's banners and content.
    @ViewBuilder private var leading: some View {
        first(bar: PrimaryTabBar(project: project, sidebar: sidebar, layout: layout))
    }

    @ViewBuilder private func first(bar: some View) -> some View {
        if let url = sidebar.quickLook.map(project.url(for:)) {
            QuickLookView(url: url).safeAreaInset(edge: .top, spacing: 0) { bar }
        } else if let buffer = shownBuffer {
            VStack(spacing: 0) {
                MissingFileBanner(project: project, buffer: buffer)
                ChangedOnDiskBanner(project: project, buffer: buffer)
                if showsBibForm {
                    BibEditorView(project: project, buffer: buffer, tables: tables, showsSource: Binding(get: { layout.bibSource }, set: { layout.bibSource = $0 }))
                } else {
                    EditorView(project: project, buffer: buffer, tables: tables, actions: actions, marks: project.lintHints(in: buffer.path) + (inlineIssues ? project.diagnostics(in: buffer.path) : []), revealToken: project.selectionRequests,
                               layout: layout, focusMode: layout.focus)
                        .overlay(alignment: .topTrailing) {
                            if BibTeX.isFormEditable(buffer.path.raw) {
                                Button("Show Form", systemImage: "list.bullet.rectangle") { layout.bibSource = false }
                                    .buttonStyle(.glass).padding(12)
                                    .help("Edit the entries in a form")
                            }
                        }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    bar
                    if !layout.focus { JumpBar(project: project, buffer: buffer, actions: actions, focused: !layout.secondFocused) }
                }
            }
        } else {
            ContentUnavailableView("No File Selected", systemImage: "doc.text").safeAreaInset(edge: .top, spacing: 0) { bar }
        }
    }
}

struct CompileStatusBadge: View {
    let status: CompileStatus

    var body: some View {
        switch status {
        case .idle:
            Label("Ready", systemImage: "checkmark.circle").foregroundStyle(.secondary)
        case .compiling:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Compiling…") }.foregroundStyle(.secondary)
        case .downloading(let package):
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Downloading \(package)") }.foregroundStyle(.secondary)
        }
    }
}

/// Opens an Open Quickly result: a file as a permanent tab (⌥: in the second pane), at a line for "name:line",
/// a symbol with its name selected, a built-in in the docs panel.
@MainActor private func openQuickly(_ r: QuickOpenResult, alternate: Bool, in window: NSWindow, project: Project, layout: EditorLayout) {
    let item = r.item
    guard let file = item.file else {
        guard let docs = TypstDocs.doc(item.name) else { return }
        let f = window.frame
        let caret = NSRect(x: f.midX - QuickOpenPanel.width / 2 + 16, y: f.maxY - f.height / 5 - QuickOpenPanel.fieldHeight, width: 1, height: QuickOpenPanel.fieldHeight)
        return DocsPanel.shared.show(doc: docs.doc, signature: docs.signature, caret: caret, in: window)
    }
    if case .bookmark(let id) = item.kind {
        if let b = project.bookmarks.first(where: { $0.id == id }) { project.reveal(b) }
        return
    }
    if let line = r.line { return project.showLine(file, line: line, column: r.column) }
    if item.kind != .file { return project.show(file, range: item.range, flash: true) }
    if alternate, file != project.selectedFile {
        if !layout.split { layout.toggleSplit(in: project) }
        layout.showSecond(file, in: project)
    } else {
        project.openPermanently(file)
    }
}
