import AppKit
import SwiftUI
import TypoKit
import TypstEngine

/// File ▸ Snapshots…: the project's local history as a sheet on its window.
struct SnapshotCommands: Commands {
    let recents: RecentProjects
    private let focus = FocusedCommandContext()

    private var context: AppCommandContext { focus.context(recents: recents) }

    var body: some Commands {
        let ctx = context
        CommandGroup(after: .newItem) {
            AppCommands.items(AppCommands.snapshots(ctx))
        }
    }
}

/// An AppKit sheet, so the window needs no state of its own for it.
@MainActor func presentSnapshots(_ project: Project) {
    guard let parent = NSApp.keyWindow, parent.attachedSheet == nil else { return }
    let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 580), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    sheet.isReleasedWhenClosed = false
    sheet.contentView = NSHostingView(rootView: SnapshotsView(project: project) { [weak parent, weak sheet] in
        if let sheet { parent?.endSheet(sheet) }
    })
    parent.beginSheet(sheet)
}

struct SnapshotsView: View {
    let project: Project
    let done: () -> Void
    @State private var snapshots: [ProjectSnapshot] = []
    @State private var differing: [Date: Int] = [:]
    @State private var selected: Date?
    @State private var files: [SnapshotFile] = []
    @State private var selectedFile: RelPath?
    @State private var compare = Compare.text
    @State private var diff: [DiffLine]?
    @AppStorage("diffSideBySide") private var sideBySide = false

    /// The right pane: the snapshot's text, or its difference to the text now or to the last commit.
    private enum Compare: Hashable { case text, now, head }
    private struct DiffKey: Hashable { let file: SnapshotFile?; let compare: Compare }

    private var file: SnapshotFile? { files.first { $0.path == selectedFile } }
    private var changed: [SnapshotFile] { files.filter { $0.state != .unchanged } }

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                List(snapshots, selection: $selected) { s in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.date, format: .relative(presentation: .named))
                        Text(summary(differing[s.id])).font(.caption).foregroundStyle(.secondary)
                    }
                    .help(s.date.formatted(date: .abbreviated, time: .standard))
                }
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 320)
                .overlay { if snapshots.isEmpty { ContentUnavailableView("No Snapshots Yet", systemImage: "clock.arrow.circlepath") } }
                List(files, selection: $selectedFile) { f in
                    Label {
                        HStack { Text(f.path.raw); Spacer(); Text(Self.title(f.state)).foregroundStyle(.secondary) }
                    } icon: {
                        Image(systemName: Self.symbol(f.state)).foregroundStyle(Self.color(f.state))
                    }
                }
                .frame(minWidth: 220, idealWidth: 280)
                VStack(spacing: 0) {
                    HStack {
                        Picker("Show", selection: $compare) {
                            Text("Text").tag(Compare.text)
                            Text("Changes Since").tag(Compare.now)
                            if project.isRepository { Text("vs. Last Commit").tag(Compare.head) }
                        }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                        .help("Changes Since: from this snapshot to the text now. vs. Last Commit: from the last commit to this snapshot.")
                        Spacer()
                        if compare != .text { DiffLayoutPicker(sideBySide: $sideBySide) }
                    }
                    .padding(8)
                    Divider()
                    if compare == .text {
                        ScrollView {
                            Text(file?.text ?? "").font(.body.monospaced()).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                        }
                    } else {
                        DiffContent(lines: file == nil ? [] : diff, sideBySide: sideBySide)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 280)
                .task(id: DiffKey(file: file, compare: compare)) { await loadDiff() }
            }
            Divider()
            HStack {
                Button("Take Snapshot Now") { Task { await project.takeSnapshot().value; await reload() } }.buttonStyle(.glass)
                Spacer()
                Button("Restore File") { if let file { restore([file]) } }.buttonStyle(.glass).disabled(file == nil || file?.state == .unchanged)
                Button("Restore All Changed Files") { restore(changed) }.buttonStyle(.glass).disabled(changed.isEmpty)
                Button("Done", action: done).keyboardShortcut(.defaultAction).buttonStyle(.glassProminent)
            }
            .padding(12)
        }
        .frame(minWidth: 760, minHeight: 440)
        .task { await reload() }
        .onChange(of: selected) { Task { await loadFiles() } }
    }

    private func loadDiff() async {
        guard compare != .text, let f = file else { diff = nil; return }
        diff = nil
        switch compare {
        case .now:
            let current = project.buffer(for: f.path)?.storage.string ?? (try? String(contentsOf: project.url(for: f.path), encoding: .utf8)) ?? ""
            diff = GitDiff.between(f.text, current)
        case .head:
            diff = GitDiff.between(await project.headText(of: f.path) ?? "", f.text)
        case .text: break
        }
    }

    private func summary(_ n: Int?) -> String {
        switch n {
        case nil: ""
        case 0: "Same as now"
        case 1: "1 file differs"
        case let n?: "\(n) files differ"
        }
    }

    private static func title(_ s: SnapshotFile.State) -> String {
        switch s { case .changed: "Changed"; case .unchanged: "Unchanged"; case .missing: "Missing" }
    }

    private static func symbol(_ s: SnapshotFile.State) -> String {
        switch s { case .changed: "pencil.circle.fill"; case .unchanged: "checkmark.circle"; case .missing: "minus.circle.fill" }
    }

    private static func color(_ s: SnapshotFile.State) -> Color {
        switch s { case .changed: .orange; case .unchanged: .secondary; case .missing: .red }
    }

    private func reload() async {
        snapshots = project.snapshots()
        if !snapshots.contains(where: { $0.id == selected }) { selected = snapshots.first?.id }
        await loadFiles()
        for s in snapshots { differing[s.id] = await project.files(in: s).filter { $0.state != .unchanged }.count }
    }

    private func loadFiles() async {
        guard let s = snapshots.first(where: { $0.id == selected }) else { files = []; return }
        let loaded = await project.files(in: s)
        if selected == s.id { files = loaded }        // a quicker click on another snapshot wins
    }

    /// Each restore is an undoable edit of that file (Cmd-Z in its editor takes it back).
    private func restore(_ targets: [SnapshotFile]) {
        Task {
            for f in targets {
                do { try await project.restore(f) } catch { showAlert("Couldn\u{2019}t Restore \u{201C}\(f.path.name)\u{201D}", error.localizedDescription) }
            }
            await reload()
        }
    }
}
