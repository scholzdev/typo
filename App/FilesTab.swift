import AppKit
import SwiftUI
import TypoKit
import TypstEngine

/// Xcode's project navigator: the project folder as the root row, then flattened 22 pt rows with the indent drawn
/// by hand. Selection is drawn by hand too (soft grey, as in Xcode; the sidebar list would paint it accent blue).
struct FilesTab: View {
    let project: Project
    let model: SidebarModel
    let controller: FilesController
    @FocusState private var focused: Bool
    @AppStorage(SettingsKey.fileExtensions) private var extensions = FileExtensions.hideTyp.rawValue

    /// One visible row; `node` is nil for the project folder.
    fileprivate struct Row: Identifiable {
        let node: FileNode?
        let depth: Int
        let name: String
        var id: String { node?.id.raw ?? "" }
        var isDirectory: Bool { node?.isDirectory ?? true }
    }

    private var filtering: Bool { !model.fileFilter.isEmpty }

    private var rows: [Row] {
        var out = [Row(node: nil, depth: 0, name: project.rootURL.lastPathComponent)]
        func add(_ nodes: [FileNode], _ depth: Int) {
            let names = Set(nodes.map(\.id.name))
            for n in nodes {
                out.append(Row(node: n, depth: depth, name: Self.displayName(n, among: names, extensions: FileExtensions(rawValue: extensions) ?? .hideTyp)))
                if n.isDirectory, filtering || model.expanded.contains(n.id) { add(n.children ?? [], depth + 1) }
            }
        }
        if model.rootExpanded || filtering { add(Self.filtered(project.files, by: model.fileFilter), 1) }
        return out
    }

    /// Extensions per the setting are hidden (never on folders); kept when a sibling has the shortened name, so two rows never read the same.
    private static func displayName(_ n: FileNode, among siblings: Set<String>, extensions: FileExtensions) -> String {
        let name = n.id.name
        guard !n.isDirectory, extensions == .hideAll || (extensions == .hideTyp && n.kind == .typst) else { return name }
        let short = (name as NSString).deletingPathExtension
        return short.isEmpty || siblings.contains(short) ? name : short
    }

    /// Matching names with their folders; a folder whose own name matches keeps its whole subtree.
    private static func filtered(_ nodes: [FileNode], by query: String) -> [FileNode] {
        guard !query.isEmpty else { return nodes }
        return nodes.compactMap { n in
            if n.id.name.localizedCaseInsensitiveContains(query) { return n }
            let kids = filtered(n.children ?? [], by: query)
            return kids.isEmpty ? nil : FileNode(id: n.id, isDirectory: true, children: kids)
        }
    }

    var body: some View {
        let rows = self.rows
        ScrollViewReader { proxy in
            // Not a List: the sidebar list style adds its own row height and margins, which Xcode's 22 pt rows don't have.
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        FileRow(row: row, project: project, model: model, controller: controller, isExpanded: isExpanded(row),
                                isSelected: row.node?.id == model.listSelection && row.node != nil,
                                pick: { pick(row) }, toggle: { toggle(row) })
                            .id(row.id)
                    }
                }
                .padding(.horizontal, 4)
            }
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            // Right-click on empty space below the rows; a row's own menu takes precedence over this one.
            .contextMenu {
                Button("New File…", systemImage: "doc.badge.plus") { controller.newFileInRoot() }
                Button("New Folder…", systemImage: "folder.badge.plus") { controller.newFolderInRoot() }
            }
            // Only published while the list has keyboard focus: the File menu's Move to Trash (Cmd-Delete) reads it, so in
            // the editor the shortcut stays "delete to line start". Not while a name is being edited either.
            .focusedValue(\.fileListFocused, model.renaming == nil)
            .onKeyPress(.return) {
                guard model.renaming == nil, model.listSelection != nil else { return .ignored }
                controller.beginRename()
                return .handled
            }
            .onKeyPress(.upArrow) { move(-1, rows, proxy) }
            .onKeyPress(.downArrow) { move(1, rows, proxy) }
            .onKeyPress(.rightArrow) { fold(open: true, rows, proxy) }
            .onKeyPress(.leftArrow) { fold(open: false, rows, proxy) }
            .onChange(of: project.selectedFile) { _, f in if let f { model.listSelection = f } }
            .onAppear { model.listSelection = model.quickLook ?? project.selectedFile ?? model.listSelection }
            .dropDestination(for: URL.self) { urls, _ in controller.drop(urls, into: nil); return true }
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        }
    }

    // MARK: Footer

    private var footer: some View {
        @Bindable var model = model
        return HStack(spacing: 6) {
            Menu {
                Button("New File", systemImage: "doc.badge.plus") { controller.newFile() }
                Button("New Folder", systemImage: "folder.badge.plus") { controller.newFolder() }
            } label: { Image(systemName: "plus").font(.system(size: 13)).frame(width: 22, height: 22).contentShape(Rectangle()) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("New File or Folder")
                .accessibilityLabel("New")
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease.circle").foregroundStyle(.secondary)
                TextField("Filter", text: $model.fileFilter).textFieldStyle(.plain).accessibilityLabel("Filter Files")
                if !model.fileFilter.isEmpty {
                    Button("Clear Filter", systemImage: "xmark.circle.fill") { model.fileFilter = "" }
                        .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 6).frame(height: 22)
            .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 6, style: .continuous))
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
    }

    // MARK: Selection and keys

    private func isExpanded(_ row: Row) -> Bool {
        guard let node = row.node else { return model.rootExpanded || filtering }
        return node.isDirectory && (filtering || model.expanded.contains(node.id))
    }

    private func toggle(_ row: Row) {
        guard let id = row.node?.id else { model.rootExpanded.toggle(); return }
        if model.expanded.contains(id) { model.expanded.remove(id) } else { model.expanded.insert(id) }
    }

    /// A click or a key move: files open (or go to Quick Look), folders and the project row only take the highlight.
    private func activate(_ row: Row) {
        if let id = row.node?.id { select(id) } else { model.listSelection = nil }
    }

    private func pick(_ row: Row) {
        focused = true
        activate(row)
    }

    private func select(_ id: RelPath?) {
        model.listSelection = id
        guard let id, !project.isDirectory(id) else { return }
        if FileKind.isText(id.raw) {
            model.quickLook = nil
            project.select(id)
        } else {
            model.quickLook = id
        }
    }

    private func current(_ rows: [Row]) -> Int? {
        guard let s = model.listSelection else { return nil }
        return rows.firstIndex { $0.node?.id == s }
    }

    private func move(_ delta: Int, _ rows: [Row], _ proxy: ScrollViewProxy) -> KeyPress.Result {
        guard model.renaming == nil else { return .ignored }
        let row = rows[min(max((current(rows) ?? 0) + delta, 0), rows.count - 1)]
        activate(row)
        proxy.scrollTo(row.id)
        return .handled
    }

    /// Right opens a folder, then steps into it. Left closes it, or steps out to its parent.
    private func fold(open: Bool, _ rows: [Row], _ proxy: ScrollViewProxy) -> KeyPress.Result {
        guard model.renaming == nil, let i = current(rows) else { return .ignored }
        let row = rows[i]
        let isOpen = isExpanded(row)
        if open {
            guard row.isDirectory else { return .handled }
            if !isOpen { toggle(row) } else if i + 1 < rows.count, rows[i + 1].depth > row.depth { activate(rows[i + 1]); proxy.scrollTo(rows[i + 1].id) }
        } else if row.isDirectory, isOpen, !filtering {
            toggle(row)
        } else if let parent = rows[..<i].last(where: { $0.depth < row.depth }) {
            activate(parent)
            proxy.scrollTo(parent.id)
        }
        return .handled
    }

    // MARK: Row

    private struct FileRow: View {
        let row: Row
        let project: Project
        let model: SidebarModel
        let controller: FilesController
        let isExpanded: Bool
        let isSelected: Bool
        let pick: () -> Void
        let toggle: () -> Void
        @State private var dropTargeted = false

        private var node: FileNode? { row.node }
        private var dropTarget: RelPath? { node.map { $0.isDirectory ? $0.id : $0.id.parent } ?? nil }

        var body: some View {
            HStack(spacing: 4) {
                Color.clear.frame(width: CGFloat(row.depth) * 14, height: 1)
                chevron
                FileIcon(kind: node?.kind ?? .folder)
                if let node, model.renaming == node.id {
                    RenameField(text: node.id.name, selectsAll: node.isDirectory,
                                commit: { controller.commitRename(node.id, to: $0) }, cancel: controller.cancelRename)
                        .frame(maxWidth: .infinity).frame(height: 20)
                } else {
                    Text(row.name).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 22)
            .background {
                let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
                ZStack {
                    shape.fill(isSelected ? Color.primary.opacity(0.1) : .clear)
                    if dropTargeted, row.isDirectory {
                        shape.fill(Color.accentColor.opacity(0.18))
                        shape.strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                }
            }
            .contentShape(Rectangle())   // the click and the double click cover the whole row
            .onTapGesture(perform: pick)
            .simultaneousGesture(TapGesture(count: 2).onEnded { open() })
            .contextMenu { menu }
            // A row is dragged as its file URL; the drop tells project URLs (move) from Finder ones (copy).
            .modifier(RowDrag(url: node.map { project.url(for: $0.id) }))
            // A folder takes drops itself; a file passes them to its folder; the project row takes them into the root.
            .dropDestination(for: URL.self) { urls, _ in controller.drop(urls, into: dropTarget); return true } isTargeted: { dropTargeted = $0 }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(row.name)
            .accessibilityValue(row.isDirectory ? (isExpanded ? "Expanded" : "Collapsed") : "")
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(.default, pick)
        }

        @ViewBuilder private var chevron: some View {
            if row.isDirectory {
                Button(action: toggle) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 12, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Collapse \(row.name)" : "Expand \(row.name)")
            } else {
                Color.clear.frame(width: 12, height: 1)
            }
        }

        /// Double click: a text file becomes a permanent tab (per setting); a folder opens or closes.
        private func open() {
            guard let node else { return toggle() }
            if node.isDirectory { return toggle() }
            guard FileKind.isText(node.id.raw) else { return }
            model.quickLook = nil
            model.listSelection = node.id
            project.select(node.id)
            if project.navigation.doubleClickOpensPermanent { project.makeTabPermanent(node.id) }
        }

        @ViewBuilder private var menu: some View {
            if let node {
                let url = project.url(for: node.id)
                if !node.isDirectory, FileKind.isText(node.id.raw) {
                    Button("Open in New Tab", systemImage: "plus.rectangle.on.rectangle") {
                        model.quickLook = nil
                        model.listSelection = node.id
                        project.openPermanently(node.id)
                    }
                    Divider()
                }
                Button("New File…", systemImage: "doc.badge.plus") { controller.newFile(near: node.id) }
                Button("New Folder…", systemImage: "folder.badge.plus") { controller.newFolder(near: node.id) }
                Divider()
                Button("Rename", systemImage: "pencil") { controller.beginRename(node.id) }
                Button("Duplicate", systemImage: "plus.square.on.square") { controller.duplicate(node.id) }
                Button("Move to Trash", systemImage: "trash") { controller.moveToTrash(node.id) }
                Divider()
                Button("Open With Default App", systemImage: "arrow.up.forward.app") { NSWorkspace.shared.open(url) }
                Button("Reveal in Finder", systemImage: "finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                if !node.isDirectory, model.git.isRepository, SourceControl.isEnabled {
                    Button("Show Git History", systemImage: "clock.arrow.circlepath") { model.git.historyOf = HistoryTarget(path: node.id.raw) }
                }
                if !node.isDirectory {
                    Button("Add File Bookmark", systemImage: "bookmark") { project.addFileBookmark(node.id) }.disabled(project.fileBookmark(node.id) != nil)
                }
                if node.kind == .typst {
                    Divider()
                    Button("Preview This Document", systemImage: "eye") { project.setMain(node.id) }.disabled(project.main == node.id)
                }
            } else {
                Button("New File…", systemImage: "doc.badge.plus") { controller.newFileInRoot() }
                Button("New Folder…", systemImage: "folder.badge.plus") { controller.newFolderInRoot() }
                Divider()
                Button("Reveal in Finder", systemImage: "finder") { NSWorkspace.shared.activateFileViewerSelecting([project.rootURL]) }
            }
        }
    }

    /// Makes a row draggable; the project row has no URL to drag.
    private struct RowDrag: ViewModifier {
        let url: URL?

        func body(content: Content) -> some View {
            if let url { content.draggable(url) } else { content }
        }
    }
}
