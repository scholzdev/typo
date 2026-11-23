import SwiftUI
import TypoKit
import UniformTypeIdentifiers
import TypstEngine

/// Xcode-style welcome window: app icon, name and version, open buttons and the recent projects.
struct WelcomeView: View {
    @Environment(RecentProjects.self) private var recents
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var selection: ProjectID?
    @FocusState private var listFocused: Bool

    private var opener: ProjectOpener { ProjectOpener(recents: recents, openWindow: openWindow) }
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
            Text("Typo").font(.system(size: 20, weight: .bold))
            Text("Version \(version)").foregroundStyle(.secondary).padding(.top, 2)
            HStack(spacing: 8) {
                Button { if opener.choose() { dismissWindow(id: "welcome") } } label: { Text("Open…").frame(maxWidth: .infinity) }
                Button { if opener.newProject() { dismissWindow(id: "welcome") } } label: { Text("New Project…").frame(maxWidth: .infinity) }
                Button { openWindow(id: "templates") } label: { Text("Templates…").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.extraLarge)
            .padding(.top, 20)
            recentList.padding(.top, 18)
        }
        .padding(.horizontal, 40)
        .padding(.top, 30)
        .padding(.bottom, 36)
        .frame(width: 440, height: 528)    // the hidden title bar still adds its 32 pt to the window
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) {
            Button { dismissWindow(id: "welcome") } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .medium)).frame(width: 22, height: 22)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .keyboardShortcut(.cancelAction)
            .help("Close")
            .padding(14)
        }
        .background(WindowChrome())
        // SwiftUI orders this window front after delivering the event, so close it one turn later.
        .onOpenURL { if opener.open($0) { Task { dismissWindow(id: "welcome") } } }
        .task {
            selection = recents.records.first?.id
            listFocused = true
        }
    }

    @ViewBuilder private var recentList: some View {
        Group {
            if recents.records.isEmpty {
                Text("No Recent Projects").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(recents.records, id: \.id, selection: $selection) { RecentRow(record: $0) }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                    .focused($listFocused)
                    .contextMenu(forSelectionType: ProjectID.self) { _ in } primaryAction: { ids in
                        if let id = ids.first { openWindow(value: id); dismissWindow(id: "welcome") }
                    }
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

private struct RecentRow: View {
    let record: RecentProjects.Record
    static let icon = NSWorkspace.shared.icon(for: UTType(filenameExtension: "typ") ?? .plainText)
    // The sandbox home is the app container, so ask the user database for the real one.
    static let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: Self.icon).resizable().frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(record.name).font(.title3)
                Text(path).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        }
        .padding(.vertical, 5)
    }

    private var path: String {
        record.rootPath.hasPrefix(Self.home + "/") ? "~" + record.rootPath.dropFirst(Self.home.count) : record.rootPath
    }
}

/// A project window without a project (restored from an older build) hands over to the welcome window.
struct EmptyWindowRedirect: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Color.clear.frame(width: 1, height: 1).onAppear {
            openWindow(id: "welcome")
            dismiss()
        }
    }
}

/// Hides the traffic lights (the view draws its own close button) and lets the background drag the window.
private struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ChromeView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class ChromeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(button)?.isHidden = true
            }
            window.isMovableByWindowBackground = true
        }
    }
}
