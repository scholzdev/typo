import AppKit
import SwiftUI
import TypoKit
import TypstEngine

/// What the bottom bar and the Format menu share with the editor: formatting commands and the selection's word count.
@MainActor @Observable final class EditorActions {
    /// Words in the prose of the current selection; nil without a selection.
    var selectedWords: Int?
    var citationPickerPresented = false
    /// Start of the heading line whose section holds the first pane's caret; nil outside any section.
    var caretHeading: Int?
    /// "Line N, Col M" or the selection summary of the focused editor; nil without one.
    var caretStatus: String?
    /// Bumped on every caret report, including a file swap that leaves the status text unchanged, so the Selection tab refreshes.
    var caretEpoch = 0
    /// Vim's mode line (`-- INSERT --`, pending keys, `:` line); nil with Vim mode off.
    var vimStatus: VimBadge?
    @ObservationIgnored weak var editor: EditorView.Coordinator?
    /// Opens the assistant and asks it to explain the editor's selection (the editor's "Explain with AI").
    @ObservationIgnored var explainSelection: (@MainActor () -> Void)?

    func format(_ command: Formatting.Command) { editor?.format(command) }
    func formatCode(selectionOnly: Bool) { editor?.formatCode(selectionOnly: selectionOnly) }

    /// Go to Line's input ("42", "42:7", "+10"): selects that line, or puts the caret at the column, and flashes it.
    @discardableResult func goToLine(_ input: String) -> Bool {
        guard let tv = editor?.textView else { return false }
        let caret = tv.selectedRange().location
        let current = tv.string.utf16.prefix(caret).count { $0 == 10 } + 1
        guard let target = QuickOpen.lineTarget(input, current: current) else { return false }
        let r = QuickOpen.range(ofLine: target.line, column: target.column, in: tv.string)
        tv.window?.makeFirstResponder(tv)
        tv.setSelectedRange(r)
        tv.scrollRangeToVisible(r)
        tv.showFindIndicator(for: r)
        return true
    }
}

/// Xcode's debug bar: a flat 28 pt strip under the editor. Formatting and insert buttons on the left; caret position,
/// word count and the git branch on the right.
struct EditorBottomBar: View {
    let project: Project
    let actions: EditorActions
    let tables: TableEditing
    let sidebar: SidebarModel
    let layout: EditorLayout

    var body: some View {
        @Bindable var sidebar = sidebar
        HStack(spacing: 2) {
            if let vim = actions.vimStatus {
                VimCapsule(badge: vim).padding(.trailing, 6)
            }
            if let hints = actions.vimStatus?.hints, !hints.isEmpty {
                VimHints(hints: hints)
            } else {
            Group {
                button("bold", "Bold", "Bold (⌘B)", .bold)
                button("italic", "Italic", "Italic (⌘I)", .italic)
                button("underline", "Underline", "Underline (⌘U)", .underline)
                Button("Insert Table", systemImage: "tablecells") { tables.insertPresented.toggle() }
                    .help("Insert Table")
                    .popover(isPresented: Binding(get: { tables.insertPresented }, set: { tables.insertPresented = $0 }), arrowEdge: .top) {
                        TableInsertPopover(insert: tables.insert)
                    }
                button("list.bullet", "Bullet List", "Bullet List", .bulletList)
                button("list.number", "Numbered List", "Numbered List", .numberedList)
                button("sum", "Math", "Math: wrap in $…$", .math)
                let enabled = project.selectedBuffer != nil && sidebar.quickLook == nil
                Button("Symbols", systemImage: "x.squareroot") { sidebar.symbolsPresented.toggle() }
                    .help("Symbols")
                    .popover(isPresented: $sidebar.symbolsPresented, arrowEdge: .top) {
                        SymbolsTab(model: sidebar, tables: tables, enabled: enabled).frame(width: 320, height: 460)
                    }
                Button("References", systemImage: "books.vertical") { sidebar.referencesPresented.toggle() }
                    .help("References")
                    .popover(isPresented: $sidebar.referencesPresented, arrowEdge: .top) {
                        ReferencesTab(project: project, model: sidebar, tables: tables, enabled: enabled).frame(width: 320, height: 460)
                    }
            }
            .labelStyle(.iconOnly).buttonStyle(.borderless).font(.system(size: 12)).frame(width: 24, height: 20)
            }
            Spacer()
            if actions.caretStatus != nil { CaretStatusButton(actions: actions, layout: layout) }
            WordCountButton(project: project, actions: actions).font(.system(size: 11))
            if sidebar.git.isRepository { BranchSwitcher(project: project, model: sidebar.git) }
            Button("Show or Hide Bottom Area", systemImage: "rectangle.bottomthird.inset.filled") { layout.bottom.isShown.toggle() }
                .labelStyle(.iconOnly).buttonStyle(.borderless).font(.system(size: 12)).frame(width: 24, height: 20)
                .foregroundStyle(layout.bottom.isShown ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .help("Show or hide the bottom area (⇧⌘Y)")
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(.background)
        .overlay(alignment: .top) { Divider() }
    }

    private func button(_ symbol: String, _ label: LocalizedStringKey, _ help: LocalizedStringKey, _ command: Formatting.Command) -> some View {
        Button(label, systemImage: symbol) { actions.format(command) }.help(help)
    }
}

/// "Line N, Col M" at the right of the bottom bar; a click opens Go to Line.
private struct CaretStatusButton: View {
    let actions: EditorActions
    let layout: EditorLayout

    var body: some View {
        Button(actions.caretStatus ?? "") { layout.quickOpen = .line }
            .labelStyle(.titleOnly).buttonStyle(.borderless).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
            .help("Go to Line (⌘L)")
    }
}

/// A floating Liquid Glass capsule of borderless controls: the glass version of a `ControlGroup` in the editor and
/// preview bars. Wrap neighbouring clusters in a `GlassEffectContainer` so their glass blends.
struct GlassCluster<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 10) { content }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .glassEffect(.regular.interactive(), in: .capsule)
    }
}

/// An on/off control inside a `GlassCluster`: a borderless button whose symbol takes the accent colour while on.
struct ClusterToggle: View {
    let title: LocalizedStringKey
    let symbol: String
    @Binding var isOn: Bool

    var body: some View {
        Button(title, systemImage: symbol) { isOn.toggle() }
            .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Where the share button's picker anchors.
@MainActor final class ViewBox { weak var view: NSView? }

private struct ShareAnchor: NSViewRepresentable {
    let box: ViewBox
    func makeNSView(context: Context) -> NSView { let v = NSView(); box.view = v; return v }
    func updateNSView(_ v: NSView, context: Context) { box.view = v }
}

/// The preview with its toolbar; the main window and the pop-out window show the same thing.
struct PreviewPane: View {
    let project: Project
    /// Moves the preview to its own window or back; the caller owns the window environment.
    let popOut: () -> Void
    /// The editor's bottom area beside the preview in the project window; the notes strip matches its height.
    var editorBottom: BottomAreaModel?

    var body: some View {
        VStack(spacing: 0) {
            PreviewView(project: project).safeAreaInset(edge: .top, spacing: 0) { PreviewToolbar(project: project, popOut: popOut) }
            if project.preview.notesShown { NotesStrip(project: project, editorBottom: editorBottom) }
        }
        .task { project.detectPresenterContent() }
    }
}

struct PreviewToolbar: View {
    let project: Project
    let popOut: () -> Void
    @Environment(\.openWindow) private var openWindow
    @State private var anchor = ViewBox()
    @State private var pagePopover = false
    @State private var pageField = ""
    private var preview: PreviewModel { project.preview }
    private var pageWidth: CGFloat { preview.pages.first?.size.width ?? 595 }
    private func percent(_ p: Int) -> String { (Double(p) / 100).formatted(.percent.precision(.fractionLength(0))) }

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            // Narrow previews get fewer clusters instead of a toolbar that runs off both sides; the rest goes into "More".
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { zoomCluster; pageCluster; Spacer(minLength: 0); actionsCluster }
                HStack(spacing: 8) { zoomCluster; pageCluster; Spacer(minLength: 0); GlassCluster { moreMenu(zoom: false) } }
                HStack(spacing: 8) { pageCluster; Spacer(minLength: 0); GlassCluster { moreMenu(zoom: true) } }
            }
        }
        .controlSize(.large)
        .padding()
    }

    private var zoomCluster: some View {
        GlassCluster {
            Button("Zoom Out", systemImage: "minus.magnifyingglass") { preview.zoom(by: 0.8) }
                .help("Zoom Out")
            Menu(percent(PreviewMath.percent(zoom: preview.zoom, fitWidth: preview.fitWidth, pageWidth: pageWidth))) {
                ForEach(PreviewMath.presets, id: \.self) { p in
                    Button(percent(p)) { preview.set(zoom: PreviewMath.zoom(percent: p, fitWidth: preview.fitWidth, pageWidth: pageWidth)) }
                }
                Divider()
                Picker("Fit", selection: Bindable(preview).fit) {
                    ForEach(PreviewFit.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                Divider()
                Toggle("Dark Pages", systemImage: "circle.lefthalf.filled", isOn: Bindable(preview).darkPages)
            }
            .menuStyle(.button)
            .monospacedDigit()
            .fixedSize()
            .help("Zoom relative to the page's natural size")
            .accessibilityLabel("Zoom")
            Button("Zoom In", systemImage: "plus.magnifyingglass") { preview.zoom(by: 1.25) }
                .help("Zoom In")
            Button("Fit Width", systemImage: "arrow.left.and.right.square") { preview.fit = .width }
                .help("Fit Width")
        }
        .labelStyle(.iconOnly)
    }

    private var pageCluster: some View {
        GlassCluster {
            ClusterToggle(title: "Page Thumbnails", symbol: "sidebar.squares.left", isOn: Bindable(preview).showsThumbnails)
                .labelStyle(.iconOnly)
                .help("Show page thumbnails")
            ClusterToggle(title: "Presenter Notes", symbol: "note.text", isOn: Binding(get: { preview.notesShown }, set: { preview.showsNotes = $0 }))
                .labelStyle(.iconOnly)
                .help("Show the notes of the slide in view")
            Button { pageField = "\(page)"; pagePopover = true } label: { Text("Page \(page) of \(preview.pages.count)").monospacedDigit().fixedSize() }
                .disabled(preview.pages.isEmpty)
                .help("Go to a page")
                .popover(isPresented: $pagePopover, arrowEdge: .bottom) {
                    HStack {
                        TextField("Page", text: $pageField).frame(width: 60).onSubmit(go)
                        Button("Go", action: go).keyboardShortcut(.defaultAction)
                    }
                    .padding(12)
                }
        }
    }

    private var actionsCluster: some View {
        GlassCluster {
            Button(popOutTitle, systemImage: preview.isPoppedOut ? "arrow.down.backward.square" : "arrow.up.forward.square", action: popOut)
                .help(preview.isPoppedOut ? "Bring the preview back to the project window" : "Open the preview in its own window")
            ClusterToggle(title: "Lock Preview", symbol: project.previewLocked ? "lock.fill" : "lock.open", isOn: Bindable(project).previewLocked)
                .help(project.previewLocked ? "Locked to \(project.main.raw). Unlock to preview the file selected in the sidebar."
                                            : "Unlocked: selecting a .typ file in the sidebar previews it.")
            ClusterToggle(title: "Follow Cursor", symbol: "text.cursor", isOn: Bindable(preview).followsCursor)
                .help("Preview follows the cursor")
            // In the project window these sit in the window toolbar; a popped-out preview has no other place for them.
            if preview.isPoppedOut {
                Button("Start Presentation", systemImage: "play.rectangle", action: present)
                    .disabled(preview.pages.isEmpty)
                    .help("Present the pages full screen")
                Button("Share PDF", systemImage: "square.and.arrow.up") { Task { await share() } }
                    .help("Share the PDF")
                    .background(ShareAnchor(box: anchor))
            }
        }
        .labelStyle(.iconOnly)
    }

    /// The actions cluster as one menu, and with `zoom` the zoom controls too.
    private func moreMenu(zoom: Bool) -> some View {
        Menu {
            if zoom {
                Button("Zoom In", systemImage: "plus.magnifyingglass") { preview.zoom(by: 1.25) }
                Button("Zoom Out", systemImage: "minus.magnifyingglass") { preview.zoom(by: 0.8) }
                Button("Fit Width", systemImage: "arrow.left.and.right.square") { preview.fit = .width }
                Toggle("Dark Pages", systemImage: "circle.lefthalf.filled", isOn: Bindable(preview).darkPages)
                Divider()
            }
            Toggle("Lock Preview", systemImage: "lock", isOn: Bindable(project).previewLocked)
            Toggle("Follow Cursor", systemImage: "text.cursor", isOn: Bindable(preview).followsCursor)
            Divider()
            Button(popOutTitle, systemImage: preview.isPoppedOut ? "arrow.down.backward.square" : "arrow.up.forward.square", action: popOut)
            if preview.isPoppedOut {
                Button("Start Presentation", systemImage: "play.rectangle", action: present).disabled(preview.pages.isEmpty)
                Button("Share PDF…", systemImage: "square.and.arrow.up") { Task { await share() } }
            }
        } label: {
            Label("More", systemImage: "ellipsis")
        }
        .menuStyle(.button).menuIndicator(.hidden).labelStyle(.iconOnly).fixedSize()
        .background(ShareAnchor(box: anchor))
        .help("More preview controls")
    }

    private var popOutTitle: String { preview.isPoppedOut ? String(localized: "Return Preview to Window") : String(localized: "Pop Out Preview") }

    private func present() { PresentationSession.start(project, presenter: false, openWindow: openWindow) }

    private var page: Int { min(max(preview.visiblePage, 0), max(preview.pages.count - 1, 0)) + 1 }

    private func go() {
        pagePopover = false
        if let n = Int(pageField.trimmingCharacters(in: .whitespaces)), !preview.pages.isEmpty {
            preview.jump(toPage: min(max(n, 1), preview.pages.count) - 1)
        }
    }

    private func share() async {
        do {
            let pdf = try await project.exportPDF()
            let url = FileManager.default.temporaryDirectory.appending(path: project.pdfFileName)
            try pdf.write(to: url, options: .atomic)
            guard let view = anchor.view else { return }
            NSSharingServicePicker(items: [url]).show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        } catch {
            showExportFailure(error)
        }
    }
}

/// Window identity of a pop-out preview: the project it shows. A different type from `ProjectID`, so
/// `openWindow(value: projectID)` keeps meaning the project window.
struct PopOutID: Hashable, Codable { let project: ProjectID }

struct PopOutWindow: View {
    let id: PopOutID
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var project: Project?

    var body: some View {
        Group {
            if let project { PreviewPane(project: project) { dismissWindow(value: id) }.navigationTitle("Preview – \(project.main.raw)") } else { ProgressView() }
        }
        .frame(minWidth: 320, minHeight: 400)
        .focusedSceneValue(\.project, project)
        .task {
            // A restored pop-out can appear before its project window has finished opening. If the project
            // is not open after a moment (or never was), the window closes itself.
            for _ in 0..<30 {
                if let p = OpenProjects.shared.projects.first(where: { $0.id == id.project }) {
                    p.preview.isPoppedOut = true
                    project = p
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            dismissWindow(value: id)
        }
        .onDisappear { project?.preview.isPoppedOut = false }
    }
}

/// Xcode's Vim capsule: grey "Vim" in Normal mode, coloured for Insert and Visual and for a command being typed.
private struct VimCapsule: View {
    let badge: VimBadge

    private var tint: Color {
        switch badge.tone {
        case .normal, .delete, .other: .secondary
        case .insert: .purple
        case .visual: .teal
        case .change, .error: .red
        }
    }

    var body: some View {
        Text(badge.title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(badge.tone == .normal || badge.tone == .other || badge.tone == .delete ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint))
            .lineLimit(1)
            .padding(.horizontal, 9).frame(height: 18)
            .background(tint.opacity(badge.tone == .normal || badge.tone == .other || badge.tone == .delete ? 0.12 : 0.22), in: Capsule())
            .contentTransition(.opacity)
            .animation(.easeOut(duration: 0.12), value: badge.title)
            .accessibilityLabel("Vim: \(badge.title)")
    }
}

/// The keys that may follow, as Xcode lists them next to the capsule: the key in bold, its meaning in grey.
private struct VimHints: View {
    let hints: [VimBadge.Hint]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(hints.enumerated()), id: \.offset) { _, h in
                HStack(spacing: 3) {
                    if !h.key.isEmpty { Text(h.key).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(.secondary) }
                    Text(h.label).font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

/// The branch capsule of the status bar: the current branch (or the short commit when detached) and a menu to switch or create.
private struct BranchSwitcher: View {
    let project: Project
    let model: GitModel
    @State private var creating = false

    var body: some View {
        Menu {
            ForEach(model.branches) { b in
                Toggle(b.name, isOn: Binding(get: { b.isCurrent }, set: { _ in switchTo(b) }))
            }
            if !model.branches.isEmpty { Divider() }
            Button("New Branch…") { creating = true }
        } label: {
            Label(model.status?.branch ?? model.detachedCommit ?? String(localized: "No commits"), systemImage: "arrow.triangle.branch")
                .font(.system(size: 11)).lineLimit(1)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Color.primary.opacity(0.06), in: .capsule)
        }
        .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden).fixedSize()
        .foregroundStyle(.secondary)
        .disabled(model.busy)
        .help("Switch or create a branch")
        .sheet(isPresented: $creating) { NewBranchSheet(project: project, model: model) }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            Task { await model.refresh(project) }
        }
    }

    private func switchTo(_ b: GitBranch) {
        guard !b.isCurrent else { return }
        if project.hasUnsavedChanges,
           !confirm("You have unsaved changes", "Switching to “\(b.name)” saves them first, and git may refuse if they conflict.", ok: "Switch Anyway") { return }
        Task { await model.run(project, "Couldn’t Switch to “\(b.name)”") { try await project.switchBranch(b.name) } }
    }
}
