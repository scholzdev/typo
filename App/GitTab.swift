import AppKit
import SwiftUI
import TypoKit
import TypstEngine

/// What the Changes tab and the toolbar label share; design/14j-git.md.
@MainActor @Observable final class GitModel {
    var isRepository = false
    /// False until the first refresh, so the Changes tab does not claim "Not a Git Repository" while git is still read.
    var loaded = false
    var status: GitStatus?
    var hasRemote = false
    var busy = false
    var message = ""
    var branches: [GitBranch] = []
    /// The short commit while HEAD is detached.
    var detachedCommit: String?
    var stashes: [GitStash] = []
    var isMerging = false
    /// Sheets of the Changes tab; on the model so the Git menu and the palette can open them.
    var showStashSheet = false
    var showNewBranchSheet = false
    /// The file whose history sheet is open; set from the Changes list and the Files context menu.
    var historyOf: HistoryTarget?
    private var generation = 0
    /// When the last automatic fetch ran; several views keep the model current, only one fetch per interval goes out.
    private var lastFetch: Date?
    private var staging: Task<Void, Never>?
    /// Staging operations not yet done; refreshes meanwhile could read git mid-way and are dropped.
    private var pendingStages = 0

    func beginStaging() { generation += 1; pendingStages += 1 }
    func endStaging() { pendingStages -= 1 }

    func refresh(_ project: Project) async {
        generation += 1
        let mine = generation
        guard project.isRepository else { isRepository = false; status = nil; loaded = true; return }
        let s = try? await project.gitStatus()
        let r = (try? await project.hasRemote()) ?? false
        let b = (try? await project.branches()) ?? []
        let head = s?.branch == nil ? await project.shortHead() : nil
        let st = (try? await project.stashes()) ?? []
        guard mine == generation, pendingStages == 0 else { return }       // a newer refresh is on its way
        isRepository = true
        loaded = true
        status = s
        hasRemote = r
        branches = b
        detachedCommit = head
        stashes = st
        isMerging = project.isMerging
        NotificationCenter.default.post(name: .gitDidRefresh, object: project)     // the editor gutters reload HEAD
    }

    /// Settings' "Fetch and refresh server status automatically": a quiet fetch at most every `interval`, never
    /// during another operation. Failures (offline, no credentials) are not shown; the next pull or push reports them.
    func fetchIfDue(_ project: Project, interval: TimeInterval = 5 * 60) async {
        guard SourceControl.fetchesAutomatically, isRepository, hasRemote, !busy else { return }
        if let lastFetch, Date().timeIntervalSince(lastFetch) < interval { return }
        lastFetch = Date()
        guard (try? await project.fetch()) != nil else { return }
        await refresh(project)
    }

    /// Runs one git operation with the spinner on, shows git's stderr on failure, then refreshes.
    func run(_ project: Project, _ title: LocalizedStringResource, _ op: () async throws -> Void) async {
        guard !busy else { return }
        busy = true
        await staging?.value                            // a commit must see every checkbox clicked before it
        do { try await op() } catch { showAlert(title, error) }
        busy = false
        await refresh(project)
    }
}

struct HistoryTarget: Identifiable {
    let path: String
    var id: String { path }
}

extension GitModel {
    /// Staging is quick and frequent, so it does not go through `run`: the checkbox shows the new state at once,
    /// nothing is disabled and no spinner shows; clicks queue up and run in order, then one refresh confirms.
    func setStaged(_ cs: [GitChange], _ on: Bool, in project: Project) {
        if var s = status {
            let ids = Set(cs.map(\.id))
            for i in s.changes.indices where ids.contains(s.changes[i].id) {
                s.changes[i].staged = on
                s.changes[i].unstaged = !on
            }
            status = s
        }
        beginStaging()                                  // a refresh already on its way would bring the old state back
        let previous = staging
        staging = Task {
            await previous?.value
            do {
                if on { try await project.stage(cs) } else { try await project.unstage(cs) }
            } catch { showAlert(on ? "Couldn’t Stage" : "Couldn’t Unstage", error) }
            endStaging()
            await refresh(project)
        }
    }
}

extension View {
    /// Keeps the model current: on appear, after git operations and, with Settings' "Refresh local status
    /// automatically", on app activation and after saves; with "Fetch and refresh server status", a fetch every few minutes.
    func gitRefresh(project: Project, model: GitModel) -> some View {
        modifier(GitRefresh(project: project, model: model))
    }
}

private struct GitRefresh: ViewModifier {
    let project: Project
    let model: GitModel
    @AppStorage(SettingsKey.gitRefreshLocal) private var refreshLocal = true
    @AppStorage(SettingsKey.gitAutoFetch) private var autoFetch = true
    @AppStorage(SettingsKey.sourceControl) private var enabled = true

    func body(content: Content) -> some View {
        content
            .task(id: enabled && refreshLocal ? project.dirtyRevision : -1) { await model.refresh(project) }
            .task(id: enabled && autoFetch) {
                guard enabled && autoFetch else { return }
                while !Task.isCancelled {
                    await model.fetchIfDue(project)
                    try? await Task.sleep(for: .seconds(60))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                guard enabled && refreshLocal else { return }
                Task { await model.refresh(project) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .gitNeedsRefresh)) { n in
                guard (n.object as? Project) === project else { return }
                Task { await model.refresh(project) }
            }
    }
}

/// "↑2 ↓1" next to the compile badge.
struct GitSyncLabel: View {
    let project: Project
    let model: GitModel

    var body: some View {
        Group {
            if let s = model.status, s.ahead > 0 || s.behind > 0 {
                Text([s.ahead > 0 ? "↑\(s.ahead)" : "", s.behind > 0 ? "↓\(s.behind)" : ""].filter { !$0.isEmpty }.joined(separator: " "))
                    .foregroundStyle(.secondary).help("Commits to push (↑) and to pull (↓)")
            }
        }
        .gitRefresh(project: project, model: model)
    }
}

struct GitTab: View {
    let project: Project
    let model: GitModel
    @State private var diffOf: GitChange?
    @State private var mergeOf: GitChange?
    @State private var addingRemote = false

    var body: some View {
        @Bindable var model = model
        Group {
            if !model.loaded {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !model.isRepository {
                ContentUnavailableView {
                    Label("Not a Git Repository", systemImage: "arrow.triangle.branch")
                } description: {
                    Text("Track versions of this project with git.")
                } actions: {
                    Button("Create Repository") {
                        Task { await model.run(project, "Couldn’t Create Repository") { try await project.initRepository(defaultBranch: SourceControl.defaultBranch) } }
                    }
                        .buttonStyle(.glass).disabled(model.busy)
                }
            } else {
                repository
            }
        }
        .sheet(item: $mergeOf) { MergeEditorSheet(project: project, model: model, change: $0) }
        .sheet(item: $diffOf) { ChangeDiffSheet(project: project, model: model, change: $0) }
        .sheet(isPresented: $model.showStashSheet) { StashSheet(project: project, model: model) }
        .sheet(isPresented: $addingRemote) { AddRemoteSheet(project: project, model: model) }
        .sheet(isPresented: $model.showNewBranchSheet) { NewBranchSheet(project: project, model: model) }
        .gitRefresh(project: project, model: model)
    }

    @AppStorage(SettingsKey.gitNavigatorOrder) private var order = GitChangeOrder.name.rawValue

    /// In Settings' navigator order: by name, or by status (conflicts first).
    private var changes: [GitChange] { (GitChangeOrder(rawValue: order) ?? .name).sorted(model.status?.changes ?? []) }

    @ViewBuilder private var repository: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            HStack {
                branchMenu
                stashMenu
                if let s = model.status, s.ahead > 0 || s.behind > 0 {
                    Text("↑\(s.ahead) ↓\(s.behind)").foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                ProgressView().controlSize(.small).opacity(model.busy ? 1 : 0)   // keeps its space: the header must not shift
            }
            .padding(8)
            if !model.isMerging, changes.contains(where: { $0.kind == .conflicted }) {
                HStack {
                    Label("Applying a stash ran into conflicts. The stash is still there.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.callout)
                    Spacer()
                    Button("Undo Apply") {
                        guard confirm("Undo applying the stash?", "Every file goes back to the last commit. The stash stays, so you can apply it again later.", ok: "Undo Apply") else { return }
                        Task { await model.run(project, "Couldn’t Undo") { try await project.undoStashApply() } }
                    }
                    .buttonStyle(.glass).controlSize(.small)
                }
                .padding(.horizontal, 8).padding(.bottom, 6)
            }
            if model.isMerging {
                HStack {
                    Label("Merging: resolve the conflicts, then commit.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.callout)
                    Spacer()
                    Button("Abort Merge") {
                        guard confirm("Abort the merge?", "Every file goes back to how it was before the merge started.", ok: "Abort Merge") else { return }
                        Task { await model.run(project, "Couldn’t Abort the Merge") { try await project.abortMerge() } }
                    }
                    .buttonStyle(.glass).controlSize(.small)
                }
                .padding(.horizontal, 8).padding(.bottom, 6)
            }
            List {
                if changes.isEmpty {
                    Text("No changes").foregroundStyle(.secondary)
                }
                ForEach(changes) { c in
                    HStack(spacing: 6) {
                        Toggle(isOn: Binding(get: { c.staged }, set: { setStaged([c], $0) })) { EmptyView() }
                            .toggleStyle(.checkbox).labelsHidden()
                            .help(c.partlyStaged ? "Partly staged: check to stage the rest" : c.staged ? "Staged for the next commit" : "Stage for the next commit")
                        Button { if c.kind == .conflicted { mergeOf = c } else { diffOf = c } } label: {
                            HStack(spacing: 6) {
                                Text(c.letter).font(.body.monospaced().bold()).foregroundStyle(color(c.kind)).frame(width: 14)
                                Text(c.path).lineLimit(1).truncationMode(.middle)
                                if c.partlyStaged { Text("partly").font(.caption).foregroundStyle(.secondary) }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .contextMenu {
                        if c.kind == .conflicted {
                            Button("Resolve in Merge Editor…") { mergeOf = c }
                            Button("Keep Mine") { resolve(c, mine: true) }
                            Button("Keep Theirs") { resolve(c, mine: false) }
                            Button("Mark as Resolved") { setStaged([c], true) }
                                .help("After editing the conflict markers away by hand")
                            Divider()
                        }
                        Button(c.staged && !c.unstaged ? "Unstage" : "Stage") { setStaged([c], !(c.staged && !c.unstaged)) }
                        Button("Show Diff") { diffOf = c }
                        Button("Show History") { model.historyOf = HistoryTarget(path: c.path) }.disabled(c.kind == .untracked)
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $model.message)
                    .font(.body).frame(height: 64)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator))
                HStack {
                    if model.hasRemote {
                        Button(commitTitle) { commit(push: false) }.buttonStyle(.glass)
                        Button(commitTitle + " & Push") { commit(push: true) }.buttonStyle(.glassProminent)
                    } else {
                        Button(commitTitle) { commit(push: false) }.buttonStyle(.glassProminent)
                        Button(commitTitle + " & Push") { commit(push: true) }.buttonStyle(.glass).disabled(true)
                    }
                }
                .help(stagedCount > 0 ? "Commits the checked files only" : "Nothing is checked, so every change is committed")
                .disabled(!canCommit)
                HStack {
                    Button("Pull") { Task { await model.run(project, "Pull Failed") { try await project.pull() } } }.buttonStyle(.glass)
                    Button("Push") { Task { await model.run(project, "Push Failed") { try await project.push() } } }.buttonStyle(.glass)
                }
                .disabled(model.busy || !model.hasRemote)
                if !model.hasRemote {
                    HStack {
                        Text("No remote").foregroundStyle(.secondary).font(.callout)
                        Button("Add Remote…") { addingRemote = true }.buttonStyle(.glass)
                    }
                }
            }
            .padding(8)
        }
    }

    private var stagedCount: Int { changes.filter(\.staged).count }

    /// "Commit 2 Files" when some are checked, "Commit All" when none are.
    private var commitTitle: String {
        switch stagedCount {
        case 0: String(localized: "Commit All")
        case 1: String(localized: "Commit 1 File")
        case let n: String(localized: "Commit \(n) Files")
        }
    }

    private var branchMenu: some View {
        Menu {
            ForEach(model.branches) { b in
                Toggle(b.name, isOn: Binding(get: { b.isCurrent }, set: { _ in switchTo(b) }))
            }
            if !model.branches.isEmpty { Divider() }
            Button("New Branch…", systemImage: "plus") { model.showNewBranchSheet = true }
        } label: {
            Label(model.status?.branch ?? "detached HEAD", systemImage: "arrow.triangle.branch").lineLimit(1).truncationMode(.middle).frame(maxWidth: 150)
        }
        .menuStyle(.button).buttonStyle(.borderless).fixedSize()
        .disabled(model.busy)
        .help("Switch or create a branch")
    }

    private var stashMenu: some View {
        Menu {
            Button("Stash Changes…", systemImage: "tray.and.arrow.down") { model.showStashSheet = true }.disabled(changes.isEmpty)
            if !model.stashes.isEmpty {
                Section("Stashes") {
                    ForEach(model.stashes) { st in
                        Menu("\(st.message) · \(st.date.formatted(.relative(presentation: .named)))") {
                            Button("Apply and Remove") { stashOp(st, "Couldn’t Apply the Stash") { try await project.applyStash(st, pop: true) } }
                            Button("Apply and Keep") { stashOp(st, "Couldn’t Apply the Stash") { try await project.applyStash(st, pop: false) } }
                            Divider()
                            Button("Delete…", role: .destructive) {
                                guard confirm("Delete the stash “\(st.message)”?", "Its changes are lost.", ok: "Delete") else { return }
                                stashOp(st, "Couldn’t Delete the Stash") { try await project.dropStash(st) }
                            }
                        }
                    }
                }
            }
        } label: {
            Label(model.stashes.isEmpty ? "Stash" : "Stash (\(model.stashes.count))", systemImage: "tray")
        }
        .menuStyle(.button).buttonStyle(.borderless).fixedSize()
        .disabled(model.busy)
        .help("Put changes aside and bring them back later")
    }

    private func stashOp(_ st: GitStash, _ title: LocalizedStringResource, _ op: @escaping () async throws -> Void) {
        Task { await model.run(project, title, op) }
    }

    private func resolve(_ c: GitChange, mine: Bool) {
        Task { await model.run(project, "Couldn’t Resolve “\(c.path)”") { try await project.resolveConflict(c.path, keepingMine: mine) } }
    }

    private func switchTo(_ b: GitBranch) {
        guard !b.isCurrent else { return }
        Task { await model.run(project, "Couldn’t Switch to “\(b.name)”") { try await project.switchBranch(b.name) } }
    }

    private func setStaged(_ cs: [GitChange], _ on: Bool) { model.setStaged(cs, on, in: project) }

    private var canCommit: Bool {
        !model.busy && !changes.isEmpty && !model.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func commit(push: Bool) {
        let text = model.message.trimmingCharacters(in: .whitespacesAndNewlines)
        let onlyStaged = stagedCount > 0
        Task {
            await model.run(project, push ? "Commit & Push Failed" : "Commit Failed") {
                if onlyStaged { try await project.commitStaged(text) } else { try await project.commitAll(text) }
                model.message = ""
                if push { try await project.push() }
            }
        }
    }

    private func color(_ k: GitChange.Kind) -> Color {
        switch k {
        case .added, .untracked: .green
        case .deleted, .conflicted: .red
        default: .orange
        }
    }
}

/// A diff in a sheet: a header, the diff, Done. `load` runs once on appear.
struct DiffSheet: View {
    let title: String
    var badge: String?
    var subtitle: String?
    /// The file to sniff for a NUL byte when the diff comes back empty.
    var binaryCheck: URL?
    let load: @MainActor () async throws -> [DiffLine]
    @Environment(\.dismiss) private var dismiss
    @AppStorage("diffSideBySide") private var sideBySide = false
    @State private var lines: [DiffLine]?
    @State private var isBinary = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if let badge { Text(badge).font(.system(.caption, design: .monospaced).bold()).foregroundStyle(.secondary) }
                Text(title).font(.headline).lineLimit(1).truncationMode(.middle)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                DiffLayoutPicker(sideBySide: $sideBySide)
            }
            .padding(12)
            Divider()
            DiffContent(lines: lines, error: error, isBinary: isBinary, sideBySide: sideBySide)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.glassProminent) }.padding(12)
        }
        .frame(minWidth: 560, idealWidth: 820, minHeight: 360, idealHeight: 560)
        .task {
            do {
                let l = try await load()
                lines = l
                if l.isEmpty, let binaryCheck { isBinary = DiffContent.looksBinary(binaryCheck) }
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct DiffLayoutPicker: View {
    @Binding var sideBySide: Bool

    var body: some View {
        Picker("Layout", selection: $sideBySide) {
            Image(systemName: "rectangle.grid.1x2").help("Unified").tag(false)
            Image(systemName: "rectangle.split.2x1").help("Side by Side").tag(true)
        }
        .pickerStyle(.segmented).labelsHidden().fixedSize()
    }
}

/// A loaded diff, unified or side by side; nil `lines` is still loading.
struct DiffContent: View {
    /// One unified line: old/new numbers from the hunk headers.
    private struct Row: Identifiable {
        let id: Int
        let kind: DiffLine.Kind
        let old: Int?
        let new: Int?
        let text: String
        var hunk: Int?
    }

    private static let charWidth: CGFloat = 7.3    // advance of 12 pt monospaced
    private static let gutterWidth: CGFloat = 92
    private static let halfGutter: CGFloat = 40

    /// A button on each hunk header (Stage / Unstage); it gets the hunk's index in the diff.
    struct HunkAction {
        let title: LocalizedStringKey
        let perform: (Int) -> Void
    }

    let lines: [DiffLine]?
    var error: String?
    var isBinary = false
    var sideBySide = false
    @AppStorage(SettingsKey.gitLocalOnLeft) private var localOnLeft = false
    var hunkAction: HunkAction?

    var body: some View {
        if let error {
            Text(error).foregroundStyle(.red).textSelection(.enabled).padding(12)
        } else if let lines {
            if lines.isEmpty {
                Text(isBinary ? "Binary file changed" : "No textual changes").foregroundStyle(.secondary)
            } else if sideBySide {
                split(GitDiff.sideBySide(lines))
            } else {
                unified(Self.rows(lines))
            }
        } else {
            ProgressView().controlSize(.small)
        }
    }

    private func unified(_ rows: [Row]) -> some View {
        GeometryReader { geo in
            let longest = rows.map { $0.text.count }.max() ?? 0
            let width = max(geo.size.width, Self.gutterWidth + CGFloat(longest) * Self.charWidth + 24)
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { r in
                        HStack(spacing: 0) {
                            if let h = r.hunk, let hunkAction { hunkButton(hunkAction, h).frame(width: Self.gutterWidth + 6) } else { gutter(r) }
                            Text(r.text.isEmpty ? " " : r.text)
                                .foregroundStyle(r.kind == .hunk ? .secondary : .primary)
                                .lineLimit(1).fixedSize()
                            Spacer(minLength: 0)
                        }
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: width, alignment: .leading)
                        .background(Self.background(r.kind))
                    }
                }
                .textSelection(.enabled)
            }
        }
    }

    private func split(_ pairs: [GitDiff.Pair]) -> some View {
        GeometryReader { geo in
            let longest = pairs.map { max(($0.old?.text.count) ?? 0, ($0.new?.text.count) ?? 0) }.max() ?? 0
            let half = max(geo.size.width / 2, Self.halfGutter + CGFloat(longest) * Self.charWidth + 16)
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let ordinals = Dictionary(uniqueKeysWithValues: pairs.filter(\.isHunk).enumerated().map { ($1.id, $0) })
                    ForEach(pairs) { p in
                        if p.isHunk {
                            HStack(spacing: 6) {
                                if let hunkAction, let h = ordinals[p.id] { hunkButton(hunkAction, h) } else { Color.clear.frame(width: Self.halfGutter) }
                                Text(p.old?.text ?? "").foregroundStyle(.secondary).lineLimit(1).fixedSize()
                                Spacer(minLength: 0)
                            }
                                .frame(width: half * 2, alignment: .leading)
                                .background(Self.background(.hunk))
                        } else {
                            // Settings' comparison view: the local (newer) revision on the left or the right.
                            let old = side(p.old, kind: p.new == nil || p.new?.text != p.old?.text ? .removed : .context, width: half)
                            let new = side(p.new, kind: p.old == nil || p.new?.text != p.old?.text ? .added : .context, width: half)
                            HStack(spacing: 0) {
                                if localOnLeft { new; Divider(); old } else { old; Divider(); new }
                            }
                        }
                    }
                }
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
            }
        }
    }

    private func side(_ line: (number: Int, text: String)?, kind: DiffLine.Kind, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text(line.map { String($0.number) } ?? "").foregroundStyle(.tertiary)
                .frame(width: Self.halfGutter - 6, alignment: .trailing).padding(.trailing, 6).selectionDisabled()
            Text(line.map { $0.text.replacingOccurrences(of: "\t", with: "    ") } ?? " ").lineLimit(1).fixedSize()
            Spacer(minLength: 0)
        }
        .frame(width: width, alignment: .leading)
        .background(line == nil ? Color.secondary.opacity(0.06) : Self.background(kind))
    }

    private func hunkButton(_ a: HunkAction, _ index: Int) -> some View {
        Button(a.title) { a.perform(index) }
            .controlSize(.mini).buttonStyle(.glass)
            .padding(.horizontal, 4)
            .selectionDisabled()
    }

    private func gutter(_ r: Row) -> some View {
        HStack(spacing: 0) {
            Text(r.old.map(String.init) ?? "").frame(width: 36, alignment: .trailing)
            Text(r.new.map(String.init) ?? "").frame(width: 36, alignment: .trailing)
            Text(r.kind == .added ? "+" : r.kind == .removed ? "\u{2212}" : "").frame(width: 20)
        }
        .foregroundStyle(.tertiary)
        .frame(width: Self.gutterWidth, alignment: .leading)
        .padding(.trailing, 6)
        .selectionDisabled()
    }

    private static func background(_ k: DiffLine.Kind) -> Color {
        switch k {
        case .added: .green.opacity(0.18)
        case .removed: .red.opacity(0.18)
        case .hunk: .secondary.opacity(0.12)
        default: .clear
        }
    }

    private static func rows(_ lines: [DiffLine]) -> [Row] {
        var old = 0, new = 0, hunks = 0
        return lines.map { l in
            let tab = l.text.replacingOccurrences(of: "\t", with: "    ")
            switch l.kind {
            case .hunk:
                // "@@ -a,b +c,d @@ context"
                let nums = l.text.split(separator: " ").dropFirst().prefix(2).map { $0.dropFirst().split(separator: ",").first.flatMap { Int($0) } ?? 0 }
                if nums.count == 2 { old = nums[0]; new = nums[1] }
                defer { hunks += 1 }
                return Row(id: l.id, kind: .hunk, old: nil, new: nil, text: l.text, hunk: hunks)
            case .added: defer { new += 1 }; return Row(id: l.id, kind: .added, old: nil, new: new, text: tab)
            case .removed: defer { old += 1 }; return Row(id: l.id, kind: .removed, old: old, new: nil, text: tab)
            case .context: defer { old += 1; new += 1 }; return Row(id: l.id, kind: .context, old: old, new: new, text: tab)
            }
        }
    }

    /// git's own test: a NUL byte in the first 8000 bytes.
    static func looksBinary(_ url: URL) -> Bool {
        guard let h = try? FileHandle(forReadingFrom: url), let d = try? h.read(upToCount: 8000) else { return false }
        return d.contains(0)
    }
}

/// A file's commits (`git log --follow`) on the left; on the right what the selected commit changed, or the
/// difference from that version to the text now.
struct GitHistorySheet: View {
    private enum Mode: Hashable { case commit, current }
    private struct Key: Hashable { let commit: GitCommit?; let mode: Mode }

    let project: Project
    let path: String
    @Environment(\.dismiss) private var dismiss
    @AppStorage("diffSideBySide") private var sideBySide = false
    @State private var commits: [GitCommit]?
    @State private var selection: GitCommit?
    @State private var mode = Mode.commit
    @State private var lines: [DiffLine]?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
                Text(path).font(.headline).lineLimit(1).truncationMode(.middle)
                Spacer()
                Picker("Show", selection: $mode) {
                    Text("Changes in Commit").tag(Mode.commit)
                    Text("Compare with Current").tag(Mode.current)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                DiffLayoutPicker(sideBySide: $sideBySide)
            }
            .padding(12)
            Divider()
            HSplitView {
                list.frame(minWidth: 220, idealWidth: 280, maxWidth: 420)
                DiffContent(lines: selection == nil ? [] : lines, error: error, sideBySide: sideBySide)
                    .overlay { if selection == nil, commits?.isEmpty == false { Text("Select a commit").foregroundStyle(.secondary) } }
                    .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.glassProminent) }.padding(12)
        }
        .frame(minWidth: 760, idealWidth: 1000, minHeight: 420, idealHeight: 620)
        .task {
            do {
                let c = try await project.history(of: path)
                commits = c
                selection = c.first
            } catch { self.error = error.localizedDescription; commits = [] }
        }
        .task(id: Key(commit: selection, mode: mode)) { await loadDiff() }
    }

    @ViewBuilder private var list: some View {
        if let commits {
            if commits.isEmpty {
                ContentUnavailableView("No History", systemImage: "clock", description: Text("This file has not been committed yet."))
            } else {
                List(commits, selection: $selection) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.subject).lineLimit(2)
                        HStack(spacing: 6) {
                            Text(c.shortHash).monospaced()
                            Text(c.author)
                            Text(c.date, format: .relative(presentation: .named))
                        }
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        if c.path != path { Text("as \(c.path)").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
                    }
                    .tag(c)
                }
            }
        } else {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func loadDiff() async {
        guard let c = selection else { lines = nil; return }
        lines = nil
        error = nil
        do {
            let l = mode == .commit ? try await project.diff(of: c) : try await project.diff(from: c, toWorkingCopyOf: path)
            guard selection == c else { return }
            lines = l
        } catch { self.error = error.localizedDescription }
    }
}

/// A change's diff with a choice of what against what. Unstaged (working tree vs index) and Staged (index vs HEAD)
/// put a Stage / Unstage button on every hunk, so part of a file goes into the next commit.
private struct ChangeDiffSheet: View {
    private enum Mode: Hashable { case all, unstaged, staged }

    let project: Project
    let model: GitModel
    let change: GitChange
    @Environment(\.dismiss) private var dismiss
    @AppStorage("diffSideBySide") private var sideBySide = false
    @State private var mode = Mode.all
    @State private var lines: [DiffLine]?
    @State private var patch: GitPatch?
    @State private var isBinary = false
    @State private var error: String?
    @State private var applying = false

    /// Hunks of new and conflicted files cannot be picked one by one.
    private var canPickHunks: Bool { change.kind != .untracked && change.kind != .conflicted }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(change.letter).font(.system(.caption, design: .monospaced).bold()).foregroundStyle(.secondary)
                Text(change.path).font(.headline).lineLimit(1).truncationMode(.middle)
                Text(String(describing: change.kind).capitalized).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if canPickHunks {
                    Picker("Show", selection: $mode) {
                        Text("All Changes").tag(Mode.all)
                        Text("Unstaged").tag(Mode.unstaged)
                        Text("Staged").tag(Mode.staged)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    .help("Unstaged and Staged let you stage or unstage single hunks")
                }
                DiffLayoutPicker(sideBySide: $sideBySide)
            }
            .padding(12)
            Divider()
            DiffContent(lines: lines, error: error, isBinary: isBinary, sideBySide: sideBySide, hunkAction: hunkAction)
                .disabled(applying)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.glassProminent) }.padding(12)
        }
        .frame(minWidth: 560, idealWidth: 820, minHeight: 360, idealHeight: 560)
        .task(id: mode) { await load() }
    }

    private var hunkAction: DiffContent.HunkAction? {
        switch mode {
        case .all: nil
        case .unstaged: DiffContent.HunkAction(title: "Stage") { apply($0) }
        case .staged: DiffContent.HunkAction(title: "Unstage") { apply($0) }
        }
    }

    private func load() async {
        error = nil
        do {
            switch mode {
            case .all:
                patch = nil
                let l = try await project.diff(of: change)
                lines = l
                if l.isEmpty, let p = RelPath(change.path) { isBinary = DiffContent.looksBinary(project.url(for: p)) }
            case .unstaged, .staged:
                let p = try await project.patch(of: change.path, staged: mode == .staged)
                patch = p
                lines = GitDiff.parse((p.header + p.hunks.flatMap { $0 }).joined(separator: "\n"))
                isBinary = false
            }
        } catch { self.error = error.localizedDescription }
    }

    private func apply(_ hunk: Int) {
        guard let patch, !applying else { return }
        let unstage = mode == .staged
        applying = true
        Task {
            do { try await project.applyHunk(hunk, of: patch, unstage: unstage) } catch {
                showAlert(unstage ? "Couldn’t Unstage the Hunk" : "Couldn’t Stage the Hunk", error)
            }
            await model.refresh(project)
            await load()
            applying = false
        }
    }
}

private struct StashSheet: View {
    let project: Project
    let model: GitModel
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stash Changes").font(.headline)
            Text("Puts every change aside, new files included, and leaves the project as of the last commit.").font(.callout).foregroundStyle(.secondary)
            TextField("Message", text: $message, prompt: Text("Half-done chapter 3")).textFieldStyle(.roundedBorder).onSubmit(stash)
            HStack {
                Spacer()
                SheetButtons(ok: "Stash", disabled: false, cancel: { dismiss() }, action: stash)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func stash() {
        let m = message
        dismiss()
        Task { await model.run(project, "Couldn’t Stash") { try await project.stash(m) } }
    }
}

struct NewBranchSheet: View {
    let project: Project
    let model: GitModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Branch").font(.headline)
            Text("Starts at the current commit and switches to it. Uncommitted changes come along.").font(.callout).foregroundStyle(.secondary)
            TextField("Name", text: $name, prompt: Text("draft/chapter-2")).textFieldStyle(.roundedBorder).onSubmit(create)
            HStack {
                Spacer()
                SheetButtons(ok: "Create", disabled: name.trimmingCharacters(in: .whitespaces).isEmpty, cancel: { dismiss() }, action: create)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func create() {
        let n = name
        guard !n.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        dismiss()
        Task { await model.run(project, "Couldn’t Create Branch") { try await project.createBranch(n) } }
    }
}

private struct AddRemoteSheet: View {
    let project: Project
    let model: GitModel
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Remote").font(.headline)
            TextField("URL", text: $url, prompt: Text("git@github.com:user/thesis.git")).textFieldStyle(.roundedBorder).onSubmit(add)
            HStack {
                Spacer()
                SheetButtons(ok: "Add", disabled: url.trimmingCharacters(in: .whitespaces).isEmpty, cancel: { dismiss() }, action: add)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func add() {
        let u = url
        dismiss()
        Task { await model.run(project, "Couldn’t Add Remote") { try await project.addRemote(u) } }
    }
}
