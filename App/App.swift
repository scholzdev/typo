import AppKit
import SwiftUI
import TypoKit
import TypoACP
import TypstEngine

@main
struct TypoApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var recents: RecentProjects
    @State private var localPackages: LocalPackagesFolder
    init() {
        // Before any reader of UserDefaults or Application Support: the copies fill what the old bundle id and the sandboxed build left behind.
        DefaultsMigration.run()
        if let pw = getpwuid(getuid()) {
            let home = URL(fileURLWithPath: String(cString: pw.pointee.pw_dir), isDirectory: true)
            SandboxMigration.run(container: home.appending(path: "Library/Containers/\(DefaultsMigration.legacyBundleID)/Data"), home: home)
        }
        _recents = State(initialValue: RecentProjects())
        TypstRuntime.warmUp()
        let folder = LocalPackagesFolder()
        _localPackages = State(initialValue: folder)
        Task { await folder.restore() }
        GitAccountStore.shared.apply()   // the Source Control accounts sign git's HTTPS requests in
    }

    var body: some Scene {
        // First scene, so SwiftUI shows it at launch when nothing is restored and on a Dock click with no windows.
        Window("Welcome to Typo", id: "welcome") { WelcomeView() }
            .windowStyle(.hiddenTitleBar)
            .windowResizability(.contentSize)
            .restorationBehavior(.disabled)
            .keyboardShortcut("1", modifiers: [.command, .shift])
            .handlesExternalEvents(matching: ["*"])
            .environment(recents)
        // One window per project; SwiftUI encodes the ProjectID for window restoration.
        WindowGroup(for: ProjectID.self) { $id in
            if let id { ProjectWindow(id: id) } else { EmptyWindowRedirect() }
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .handlesExternalEvents(matching: [])    // opened files go to the welcome window, never to an empty project window
        .defaultSize(width: 1280, height: 820)
        .environment(recents)
        .commands {
            AboutCommands()
            ProjectCommands(recents: recents)
            ReferenceCommands(recents: recents)
            TabCommands(recents: recents)
            ExportCommands(recents: recents)
            SnapshotCommands(recents: recents)
            GitCommands(recents: recents)
            TextEditingCommands()    // Find, Find Next, Use Selection for Find reach the text view's find bar
            EditorComfortCommands(recents: recents)
            MultiCursorCommands()
        }
        // The preview in its own window; it shows the PreviewModel of the already open project.
        WindowGroup("Preview", for: PopOutID.self) { $id in
            if let id { PopOutWindow(id: id) }
        }
        .defaultSize(width: 720, height: 900)
        // The speaker's companion to the presentation, on the project window's screen.
        WindowGroup("Presenter View", for: PresenterID.self) { $id in
            if let id { PresenterWindow(id: id) }
        }
        .defaultSize(width: 1100, height: 700)
        .restorationBehavior(.disabled)
        Window("New Project from Template", id: "templates") { TemplateChooser() }
            .defaultSize(width: 900, height: 620)
            .restorationBehavior(.disabled)
            .environment(recents)
        Window("Acknowledgements", id: "acknowledgements") { AcknowledgementsView() }
            .windowResizability(.contentSize)
            .restorationBehavior(.disabled)
        Settings { SettingsView().environment(localPackages) }
            .defaultSize(width: 780, height: 560)
            .windowResizability(.contentMinSize)
    }
}

extension FocusedValues {
    @Entry var project: Project?
    @Entry var tables: TableEditing?
    @Entry var editorActions: EditorActions?
    @Entry var files: FilesController?
    /// True only while the sidebar file list has keyboard focus.
    @Entry var fileListFocused: Bool?
    /// The window's sidebar, for commands that switch its tab or drive git (`SidebarModel.git`).
    @Entry var sidebar: SidebarModel?
}

/// Projects with a live window, so quit can save them all and sudden termination can be held.
@MainActor final class OpenProjects {
    static let shared = OpenProjects()
    private(set) var projects: [Project] = []
    private var holding = false

    func add(_ p: Project) { projects.append(p); refresh() }
    func remove(_ p: Project) { projects.removeAll { $0 === p }; refresh() }

    /// disable/enableSuddenTermination are counted, so toggle at most once per state change.
    func refresh() {
        let dirty = projects.contains { $0.hasUnsavedChanges }
        guard dirty != holding else { return }
        holding = dirty
        if dirty { ProcessInfo.processInfo.disableSuddenTermination() } else { ProcessInfo.processInfo.enableSuddenTermination() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false    // the editor has its own tabs (design/14h); no native Show Tab Bar
        AppAppearance.apply()
        _ = Updates.shared    // starts the daily update check
        NotificationCenter.default.addObserver(forName: NSApplication.didUpdateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { SystemCloseItem.suppress() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ACPProcess.shutdownAll()    // npx, node and the agent of every window
    }

    func applicationShouldTerminate(_ app: NSApplication) -> NSApplication.TerminateReply {
        let projects = OpenProjects.shared.projects.filter(\.hasUnsavedChanges)
        guard !projects.isEmpty else { return .terminateNow }
        Task {
            for p in projects { await saveUntilResolved(p) }
            app.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

/// Saves everything; on failure an app-modal alert names the file and error. Retry tries again, and only
/// Discard Changes gives up, so nothing is lost silently. The caller's task keeps the Project alive meanwhile.
@MainActor func saveUntilResolved(_ project: Project) async {
    await confirmMissingFiles(project)
    await confirmChangedFiles(project)
    while true {
        do { return try await project.saveAll() } catch {
            if !confirm("Couldn't Save Changes", verbatim: project.saveError ?? "\(error)", ok: "Retry", cancel: "Discard Changes") { return }
        }
    }
}

struct ProjectWindow: View {
    let id: ProjectID
    @Environment(RecentProjects.self) private var recents
    @State private var project: Project?
    @State private var failed = false

    var body: some View {
        Group {
            if let project {
                ProjectView(project: project)
                    .onChange(of: project.hasUnsavedChanges) { OpenProjects.shared.refresh() }
            } else if failed {
                ContentUnavailableView("Project Unavailable", systemImage: "folder.badge.questionmark",
                                       description: Text("The folder could not be opened. It may have been moved or deleted."))
            } else {
                ProgressView()
            }
        }
        .frame(minWidth: 900, minHeight: 500)
        .task(id: id) {
            do {
                let p = try await Project.open(id, recents: recents, textFileSettings: FilePreferences.current)
                OpenProjects.shared.add(p)
                project = p
            } catch { failed = true }
        }
        .onDisappear {
            guard let project else { return }
            dismissWindow(value: PopOutID(project: id))
            dismissWindow(value: PresenterID(project: id))
            PresentationSession.discard(id)
            Task {
                await saveUntilResolved(project)
                OpenProjects.shared.remove(project)
            }
        }
        .focusedSceneValue(\.project, project)
        .onOpenURL { ProjectOpener(recents: recents, openWindow: openWindow).open($0) }
        #if DEBUG
        .background(ScreenshotFrame())
        #endif
    }

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
}

#if DEBUG
/// `-screenshotWindowFrame "x y w h"` (screen points, origin bottom left) puts a project window there once, so the
/// docs screenshots come out the same size on every run.
private struct ScreenshotFrame: NSViewRepresentable {
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ nsView: Probe, context: Context) {}

    final class Probe: NSView {
        private var done = false
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard !done, let window, let spec = UserDefaults.standard.string(forKey: "screenshotWindowFrame") else { return }
            let v = spec.split(separator: " ").compactMap { Double($0) }
            guard v.count == 4 else { return }
            done = true
            DispatchQueue.main.async { window.setFrame(NSRect(x: v[0], y: v[1], width: v[2], height: v[3]), display: true) }
        }
    }
}
#endif
