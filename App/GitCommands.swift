import AppKit
import SwiftUI
import TypoKit

/// The Git menu; the same commands are in the command palette.
struct GitCommands: Commands {
    let recents: RecentProjects
    private let focus = FocusedCommandContext()
    /// Settings › Source Control › Enable source control; off, the menu and the palette's git commands go away.
    @AppStorage(SettingsKey.sourceControl) private var sourceControl = true

    private var context: AppCommandContext { focus.context(recents: recents) }

    var body: some Commands {
        let ctx = context
        if sourceControl {
            CommandMenu("Git") {
                AppCommands.items(AppCommands.git(ctx))
            }
        }
    }
}

extension AppCommands {
    /// Git on the focused window's project. Operations go through `GitModel.run` (spinner, alert, refresh); the ones
    /// that need input open the Changes tab and its sheet.
    static func git(_ ctx: AppCommandContext) -> [[AppCommand]] {
        guard SourceControl.isEnabled else { return [] }
        let project = ctx.project, sidebar = ctx.sidebar, model = sidebar?.git
        let repo = ctx.isCatalog || (project != nil && model?.isRepository == true)
        let idle = repo && model?.busy == false
        let remote = idle && model?.hasRemote == true
        let hasChanges = !(model?.status?.changes.isEmpty ?? true)
        func changesTab() { sidebar?.tab = .changes }
        func run(_ title: LocalizedStringResource, _ op: @escaping (Project) async throws -> Void) {
            guard let project, let model else { return }
            Task { await model.run(project, title) { try await op(project) } }
        }

        guard repo else {
            return [[AppCommand(menu: "Git", title: "Create Git Repository", systemImage: "arrow.triangle.branch", isEnabled: project != nil && sidebar != nil) {
                changesTab()
                run("Couldn’t Create Repository") { try await $0.initRepository(defaultBranch: SourceControl.defaultBranch) }
            }]]
        }
        let current = project?.focusedEditorFile ?? project?.selectedFile
        let branches = (model?.branches ?? []).filter { !$0.isCurrent }
        return [
            [AppCommand(menu: "Git", title: "Show Changes", systemImage: "plusminus", shortcut: KeyboardShortcut("c", modifiers: [.command, .option])) { changesTab() },
             AppCommand(menu: "Git", title: "Show File History", systemImage: "clock.arrow.circlepath", isEnabled: current != nil) {
                 if let current { model?.historyOf = HistoryTarget(path: current.raw) }
             }],
            [AppCommand(menu: "Git", title: "Pull", systemImage: "arrow.down.circle", shortcut: KeyboardShortcut("x", modifiers: [.command, .option]), isEnabled: remote) {
                 run("Pull Failed") { try await $0.pull() }
             },
             AppCommand(menu: "Git", title: "Push", systemImage: "arrow.up.circle", isEnabled: remote) { run("Push Failed") { try await $0.push() } }],
            [AppCommand(menu: "Git", title: "Stash Changes…", systemImage: "tray.and.arrow.down", isEnabled: idle && hasChanges) {
                 changesTab(); model?.showStashSheet = true
             },
             AppCommand(menu: "Git", title: "New Branch…", systemImage: "plus", isEnabled: idle) { changesTab(); model?.showNewBranchSheet = true }]
                + branches.map { b in
                    AppCommand(menu: "Git", title: "Switch to “\(b.name)”", idTitle: "Switch to “\(b.name)”", systemImage: "arrow.triangle.branch", isEnabled: idle) {
                        run("Couldn’t Switch to “\(b.name)”") { try await $0.switchBranch(b.name) }
                    }
                },
        ]
    }

    static let gitHelpTexts: [String: LocalizedStringResource] = [
        "Git/Create Git Repository": "Starts tracking this project's versions with git.",
        "Git/Show Changes": "Opens the Changes tab: changed files, staging and the commit message.",
        "Git/Show File History": "Lists the commits that changed the current file, with the diff of each.",
        "Git/Pull": "Fetches commits from the remote and fast-forwards to them.",
        "Git/Push": "Sends your commits to the remote.",
        "Git/Stash Changes…": "Puts every change aside, new files included, to bring back later.",
        "Git/New Branch…": "Creates a branch at the current commit and switches to it.",
    ]
}
