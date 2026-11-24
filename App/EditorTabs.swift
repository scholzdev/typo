import AppKit
import SwiftUI
import TypoKit
import TypstEngine

/// A pane's tab bar in the Xcode style: equal-width tabs over the strip's whole width on one grey track. The selected tab
/// of the focused pane is a raised white capsule. The preview tab is in italics, unsaved text shows a dot;
/// the close button shows at the tab's leading end on hover.
struct EditorTabBar<Trailing: View>: View {
    let tabs: TabList
    let active: RelPath?
    let project: Project
    /// Whether this pane has the caret; the other pane's selected tab stays flat.
    var focused = true
    let select: (RelPath) -> Void
    let makePermanent: (RelPath) -> Void
    let togglePin: (RelPath) -> Void
    let close: (RelPath) -> Void
    let closeOthers: (RelPath) -> Void
    @ViewBuilder let trailing: Trailing

    var body: some View {
        _ = project.dirtyRevision
        return HStack(spacing: 0) {
            // As in Xcode the tabs share the strip's whole width on one grey track; many tabs get narrower, not scrolled.
            HStack(spacing: 0) {
                ForEach(tabs.paths, id: \.self) { p in tab(p) }
            }
            .background(Color.primary.opacity(0.06), in: Capsule())
            .padding(.leading, 6)
            trailing.padding(.horizontal, 8)
        }
        .frame(height: 30)
    }

    private func tab(_ p: RelPath) -> some View {
        let pinned = tabs.pinned.contains(p)
        return EditorTab(title: tabs.title(of: p), kind: FileKind(path: p.raw, isDirectory: false),
                         italic: p == tabs.preview, pinned: pinned, focused: focused,
                         dirty: project.buffer(for: p)?.isDirty == true, selected: p == active,
                         select: { select(p) }, makePermanent: { makePermanent(p) }, close: { close(p) })
            .contextMenu {
                Button("Close Tab", systemImage: "xmark") { close(p) }.disabled(pinned)
                Button("Close Other Tabs", systemImage: "rectangle.stack.badge.minus") { closeOthers(p) }
                    .disabled(!tabs.paths.contains { $0 != p && !tabs.pinned.contains($0) })
                Divider()
                Button(pinned ? "Unpin Tab" : "Pin Tab", systemImage: pinned ? "pin.slash" : "pin") { togglePin(p) }
            }
    }
}

/// One tab: icon, title and unsaved dot in the middle; the close button (hover) and the pin at its ends.
private struct EditorTab: View {
    let title: String
    let kind: FileKind
    let italic: Bool
    let pinned: Bool
    let focused: Bool
    let dirty: Bool
    let selected: Bool
    let select: () -> Void
    let makePermanent: () -> Void
    let close: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 5) {
            FileIcon(kind: kind).opacity(focused ? 1 : 0.6)
            Text(title).italic(italic).lineLimit(1).truncationMode(.middle)
            if dirty { Circle().fill(.secondary).frame(width: 6, height: 6).accessibilityLabel("Unsaved changes") }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 22)          // room for the close button and the pin at the two ends
        .frame(maxWidth: .infinity)
        .frame(height: 24)
        .overlay(alignment: .leading) {
            if hovering && !pinned {
                Button("Close Tab", systemImage: "xmark") { close() }
                    .labelStyle(.iconOnly).buttonStyle(.plain).font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                    .frame(width: 22, height: 24).contentShape(Rectangle())
            }
        }
        .overlay(alignment: .trailing) {
            if pinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.secondary).frame(width: 22).accessibilityLabel("Pinned") }
        }
        .background { if selected { capsule } }
        .foregroundStyle(selected && focused ? .primary : .secondary)
        .contentShape(.capsule)
        // Selects on mouse down like Xcode, not on mouse up; and not as a tap exclusive with the double tap, which
        // would wait out the double-click interval first.
        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in if !selected { select() } })
        .simultaneousGesture(TapGesture(count: 2).onEnded { makePermanent() })
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .overlay { if !pinned { MiddleClick { close() } } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { select() }
        .accessibilityAction(named: "Close Tab") { if !pinned { close() } }
    }

    @ViewBuilder private var capsule: some View {
        if focused {
            Capsule().fill(Color(nsColor: .textBackgroundColor))
                .shadow(color: .black.opacity(0.16), radius: 1.5, y: 0.5)
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06)))
        } else {
            Capsule().fill(Color.primary.opacity(0.08))
        }
    }
}

/// Xcode's jump bar under the first pane's tabs: project › folders › file › the heading around the caret. Each
/// segment opens a menu of its siblings: the files of that folder, or the file's headings.
struct JumpBar: View {
    let project: Project
    let buffer: Buffer
    /// Read here, not by the pane: a caret moving into another section then redraws only this bar.
    let actions: EditorActions
    /// Whether the pane has the caret: crumbs are primary then, secondary otherwise.
    var focused = true

    var body: some View {
        let dirs = directories(of: buffer.path)
        HStack(spacing: 4) {
            Menu {
                ForEach(project.tabs.paths, id: \.self) { p in
                    Button(p.raw, systemImage: "doc") { project.select(p) }.disabled(p == buffer.path)
                }
            } label: { Label("Related Items", systemImage: "square.grid.2x2").labelStyle(.iconOnly).foregroundStyle(.secondary) }
                .menuStyle(.button).buttonStyle(.accessoryBar).menuIndicator(.hidden).fixedSize()
                .padding(.trailing, 2)
            ViewThatFits(in: .horizontal) {
                ForEach(0...dirs.count, id: \.self) { collapsed in path(dirs, collapsing: collapsed) }
            }
            Spacer(minLength: 0)
            issueNavigation
        }
        .font(.system(size: 11))
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(height: 24)
    }

    /// "‹ ⚠ ›": previous issue, the worst severity in this file, next issue.
    @ViewBuilder private var issueNavigation: some View {
        let issues = project.diagnostics(in: buffer.path)
        if !issues.isEmpty {
            let hasError = issues.contains { $0.severity == .error }
            HStack(spacing: 2) {
                issueButton("Previous Issue", "chevron.left", forward: false, issues)
                Image(systemName: hasError ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(hasError ? .red : .yellow)
                    .accessibilityLabel(hasError ? "Errors in this file" : "Warnings in this file")
                issueButton("Next Issue", "chevron.right", forward: true, issues)
            }
        }
    }

    private func issueButton(_ title: LocalizedStringKey, _ symbol: String, forward: Bool, _ issues: [Diagnostic]) -> some View {
        Button(title, systemImage: symbol) {
            let caret = actions.editor?.textView?.selectedRange().location ?? 0
            func offset(_ d: Diagnostic) -> Int? { if case .project(let l) = d.origin { l.range.location } else { nil } }
            guard let at = IssueNavigation.target(offsets: issues.compactMap(offset), caret: caret, forward: forward),
                  let d = issues.first(where: { offset($0) == at }) else { return }
            project.reveal(d)
        }
        .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
        .font(.caption.weight(.semibold)).frame(width: 18)
        .help(title)
    }

    /// The project folder, then each folder of the path, with the path to list its children.
    private func directories(of path: RelPath) -> [(name: String, dir: String)] {
        let folders = path.raw.split(separator: "/").dropLast().map(String.init)
        return [(projectName(path), "")] + folders.indices.map { (folders[$0], folders[...$0].joined(separator: "/")) }
    }

    /// The first `collapsed` directories become one "…" crumb.
    private func path(_ dirs: [(name: String, dir: String)], collapsing collapsed: Int) -> some View {
        let file = buffer.path
        let regions = buffer.headingRegions
        let heading = actions.caretHeading
        return HStack(spacing: 2) {
            if collapsed > 0 {
                segment("…", icon: EmptyView()) { fileMenu(children(of: dirs[collapsed - 1].dir)) }
                chevron
            }
            ForEach(Array(dirs.enumerated().dropFirst(collapsed)), id: \.offset) { _, d in
                segment(d.name, icon: d.dir.isEmpty ? AnyView(projectIcon) : AnyView(folderIcon)) { fileMenu(children(of: d.dir)) }
                chevron
            }
            segment(file.raw.split(separator: "/").last.map(String.init) ?? file.raw, icon: FileIcon(kind: FileKind(path: file.raw, isDirectory: false))) {
                fileMenu(children(of: dirs.last?.dir ?? ""))
            }
            if let heading, let region = regions.first(where: { $0.heading == heading }) {
                chevron
                segment(title(of: region), icon: Image(systemName: "number.square.fill").foregroundStyle(.purple)) { headingMenu(regions) }
            } else if !regions.isEmpty {
                chevron
                segment(String(localized: "No Selection"), icon: EmptyView()) { headingMenu(regions) }.foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(focused ? .primary : .secondary)
    }

    private var projectIcon: some View { Image(systemName: "text.book.closed.fill").foregroundStyle(.blue) }
    private var folderIcon: some View { Image(systemName: "folder.fill").foregroundStyle(.blue) }
    private var chevron: some View { Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary).accessibilityHidden(true) }

    private func segment(_ title: String, icon: some View, @ViewBuilder menu: () -> some View) -> some View {
        // A Menu label is drawn as a template, which loses the icons' colours: draw the crumb and lay the menu over it.
        HStack(spacing: 4) {
            icon.imageScale(.small)
            Text(title)
        }
        .fixedSize()
        .overlay {
            Menu { menu() } label: { Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity) }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                .accessibilityLabel(title)
        }
    }

    /// The project folder's name: the file's URL with its relative path taken off.
    private func projectName(_ path: RelPath) -> String {
        var url = project.url(for: path)
        for _ in path.raw.split(separator: "/") { url.deleteLastPathComponent() }
        return url.lastPathComponent
    }

    private func children(of folder: String) -> [FileNode] {
        guard !folder.isEmpty else { return project.files }
        var nodes = project.files
        var prefix = ""
        for part in folder.split(separator: "/") {
            prefix += prefix.isEmpty ? String(part) : "/" + part
            guard let next = nodes.first(where: { $0.isDirectory && $0.id.raw == prefix })?.children else { return [] }
            nodes = next
        }
        return nodes
    }

    /// Folders as submenus, text files as items; other files are left out (they open in Quick Look from the sidebar).
    private func fileMenu(_ nodes: [FileNode]) -> AnyView {
        AnyView(ForEach(nodes) { node in
            let name = node.id.raw.split(separator: "/").last.map(String.init) ?? node.id.raw
            if node.isDirectory {
                Menu(name, systemImage: "folder") { fileMenu(node.children ?? []) }
            } else if FileKind.isText(node.id.raw) {
                Button(name) { project.select(node.id) }
                    .disabled(node.id == buffer.path)
            }
        })
    }

    private func headingMenu(_ regions: [FoldRegion]) -> some View {
        ForEach(regions, id: \.heading) { r in
            Button(String(repeating: "    ", count: max(r.level - 1, 0)) + title(of: r)) {
                project.show(buffer.path, range: NSRange(location: r.heading, length: 0))
            }
        }
    }

    /// The heading line without its `=` markers.
    private func title(of region: FoldRegion) -> String {
        let text = buffer.storage.string as NSString
        guard region.heading < text.length else { return "" }
        let line = text.substring(with: text.lineRange(for: NSRange(location: region.heading, length: 0)))
        let t = line.drop { $0 == "=" || $0 == " " }.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? String(localized: "Untitled") : t
    }
}

/// The first pane's bar. Hidden in Focus Mode; no tab is active while a Quick Look file is shown.
struct PrimaryTabBar: View {
    let project: Project
    let sidebar: SidebarModel
    let layout: EditorLayout

    var body: some View {
        // Like Xcode, the strip shows only with more than one tab; the jump bar is then the top row.
        if !layout.focus && project.tabs.paths.count > 1 {
            EditorTabBar(tabs: project.tabs, active: sidebar.quickLook == nil ? project.selectedFile : nil, project: project, focused: !layout.secondFocused,
                         select: { sidebar.quickLook = nil; project.selectedFile = $0 }, makePermanent: project.makeTabPermanent,
                         togglePin: project.togglePinTab,
                         close: project.closeTab, closeOthers: project.closeOtherTabs) {
                Button("New Tab", systemImage: "plus") { layout.quickOpen = .files }
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                    .help("Open a file in a new tab (⌘T)")
            }
        }
    }
}

/// File-menu Close Tab (⌘W; the system Close is hidden by `SystemCloseItem`; Close Window is ⇧⌘W) and the tab switching shortcuts.
struct TabCommands: Commands {
    let recents: RecentProjects
    @ObservedObject private var shortcuts = ShortcutStore.shared   // rebuilds the menus when a shortcut changes
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.project) private var project
    @FocusedValue(\.tables) private var tables
    @FocusedValue(\.editorActions) private var editor
    @FocusedValue(\.files) private var files
    @FocusedValue(\.fileListFocused) private var fileListFocused
    @FocusedValue(\.editorLayout) private var layout

    private var context: AppCommandContext {
        AppCommandContext(project: project, tables: tables, editor: editor, files: files, fileListFocused: fileListFocused, layout: layout, recents: recents, openWindow: openWindow)
    }

    var body: some Commands {
        let ctx = context
        CommandGroup(after: .newItem) {    // .saveItem never renders here; see SystemCloseItem
            Divider()
            AppCommands.items(AppCommands.tabs(ctx))
        }
        CommandGroup(after: .windowArrangement) {
            Divider()
            AppCommands.items(AppCommands.tabSwitching(ctx))
        }
    }
}

/// The system File > Close (and Close All) would also claim ⌘W and ⇧⌘W. SwiftUI rebuilds the main menu at will, so
/// the AppDelegate re-hides them after every event (cheap: a few menus, a few items).
@MainActor enum SystemCloseItem {
    static func suppress() {
        let close = [#selector(NSWindow.performClose(_:)), Selector(("closeAll:"))]
        for menu in NSApp.mainMenu?.items.compactMap(\.submenu) ?? [] {
            for item in menu.items where item.action.map(close.contains) == true && item.target == nil {
                if !item.isHidden { item.isHidden = true }
                if !item.keyEquivalent.isEmpty { item.keyEquivalent = "" }
            }
        }
    }
}

/// SwiftUI has no middle-click gesture. The view takes part in hit testing only while a middle-button event is being
/// dispatched, so left and right clicks (select, double click, context menu) fall through to the tab beneath.
private struct MiddleClick: NSViewRepresentable {
    let action: () -> Void

    final class View: NSView {
        var action: () -> Void = {}
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let e = NSApp.currentEvent, e.buttonNumber == 2,
                  [.otherMouseDown, .otherMouseUp, .otherMouseDragged].contains(e.type) else { return nil }
            return super.hitTest(point)
        }
        override func otherMouseUp(with event: NSEvent) {
            if event.buttonNumber == 2, bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
        }
    }

    func makeNSView(context: Context) -> View { View() }
    func updateNSView(_ v: View, context: Context) { v.action = action }
}
