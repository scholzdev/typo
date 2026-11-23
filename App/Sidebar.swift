import AppKit
import Quartz
import SwiftUI
import TypoKit
import TypstEngine

enum SidebarTab: CaseIterable, Identifiable {
    case files, search, outline, issues, bookmarks, changes
    var id: Self { self }
    var symbol: String {
        switch self {
        case .files: "folder"
        case .search: "magnifyingglass"
        case .outline: "list.bullet.indent"
        case .issues: "exclamationmark.triangle"
        case .bookmarks: "bookmark"
        case .changes: "arrow.triangle.branch"
        }
    }
    var title: String {
        switch self {
        case .files: "Files"
        case .search: "Search"
        case .outline: "Outline"
        case .issues: "Issues"
        case .bookmarks: "Bookmarks"
        case .changes: "Changes"
        }
    }
}

/// What the sidebar tabs keep while another tab is showing.
@MainActor @Observable final class SidebarModel {
    var tab: SidebarTab = .files
    var quickLook: RelPath?
    /// The selected row of the Files tab: a file or a folder (`project.selectedFile` is only the open file).
    var listSelection: RelPath?
    var expanded: Set<RelPath> = []
    /// The project folder row at the top of the Files tab.
    var rootExpanded = true
    /// The row being renamed inline.
    var renaming: RelPath?
    /// The watcher saw changes while a name was being edited; the tree is rescanned when editing ends.
    var pendingRefresh = false
    var searchQuery = ""
    /// The Files footer's name filter.
    var fileFilter = ""
    /// The Bookmarks footer's filter and its "incomplete only" toggle.
    var bookmarkFilter = ""
    var bookmarksIncompleteOnly = false
    var searchOptions = SearchOptions()
    var searchOutcome: SearchOutcome?
    /// The Search tab lists text matches or, like Xcode's Find navigator, the last Find References.
    var searchShowsReferences = false
    /// The Search tab's Replace mode and its "With" text.
    var searchReplaces = false
    var replaceText = ""
    /// The format bar's Symbols and References popovers.
    var symbolsPresented = false
    var referencesPresented = false
    var symbolQuery = ""
    let recents = RecentSymbols()
    var referenceQuery = ""
    var bibFiles: [BibFile] = []
    let git = GitModel()
}

struct SidebarView: View {
    let project: Project
    let model: SidebarModel
    let files: FilesController
    @AppStorage(SettingsKey.sourceControl) private var sourceControl = true

    // The macOS tab bar shows a tab's title only, never its image: the titles are the symbols' characters in the system font.
    private static let glyph: [SidebarTab: String] = [.files: "\u{100215}", .search: "\u{1002AB}", .outline: "\u{1002F1}",
                                                      .issues: "\u{1001FE}", .bookmarks: "\u{10025E}", .changes: "\u{100660}"]

    var body: some View {
        @Bindable var model = model
        @Bindable var git = model.git
        VStack(spacing: 0) {
            // The system's tab bar, as in Xcode's navigator: its glass selection follows the pointer while it is held.
            TabView(selection: $model.tab) {
                ForEach(SidebarTab.allCases.filter { $0 != .changes || sourceControl }) { tab in
                    Tab(value: tab) {
                        Group {
                            switch tab {
                            case .files: FilesTab(project: project, model: model, controller: files)
                            case .search: SearchTab(project: project, model: model)
                            case .outline: OutlineTab(project: project)
                            case .issues: DiagnosticsView(project: project)
                            case .bookmarks: BookmarksTab(project: project, model: model)
                            case .changes: GitTab(project: project, model: model.git)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } label: {
                        // The glyph is only for the eye; VoiceOver reads the tab's name.
                        Text(Self.glyph[tab] ?? tab.title).accessibilityLabel(tab.title)
                    }
                    .badge(tab == .issues ? errorCount : 0)
                }
            }
        }
        .onChange(of: sourceControl, initial: true) { _, on in if !on, model.tab == .changes { model.tab = .files } }
        .onChange(of: model.tab) { _, tab in if tab == .changes, !sourceControl { model.tab = .files } }
        .listStyle(.sidebar)
        .sheet(item: $git.historyOf) { GitHistorySheet(project: project, path: $0.path) }
        .font(.system(size: 13))
        .environment(\.defaultMinListRowHeight, 22)    // native sidebar rows: ~22-28 pt, Finder and Xcode navigator
        // "Show in Sidebar" of the Find References panel.
        .onChange(of: ReferenceResults.of(project).revealRequests) {
            model.searchShowsReferences = true
            model.searchReplaces = false
            model.tab = .search
        }
    }

    private var errorCount: Int { project.diagnostics.filter { $0.severity == .error }.count }
}

/// The inline rename field: Return commits, Esc cancels, losing focus commits (as in Finder). The part of the
/// name before the extension is preselected.
struct RenameField: NSViewRepresentable {
    let text: String
    let selectsAll: Bool
    let commit: (String) -> Void
    let cancel: () -> Void

    final class Field: NSTextField {
        var selectedLength = 0
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.makeFirstResponder(self)
            currentEditor()?.selectedRange = NSRange(location: 0, length: selectedLength)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: RenameField
        private var finished = false
        init(_ parent: RenameField) { self.parent = parent }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                finished = true
                parent.commit(textView.string)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                finished = true
                parent.cancel()
                return true
            default:
                return false
            }
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard !finished, let field = obj.object as? NSTextField else { return }
            finished = true
            parent.commit(field.stringValue)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> Field {
        let f = Field(string: text)
        let ns = text as NSString
        let ext = ns.pathExtension
        f.selectedLength = selectsAll || ext.isEmpty || ns.length == ext.count + 1 ? ns.length : ns.length - ext.count - 1
        f.delegate = context.coordinator
        f.font = .systemFont(ofSize: 13)
        f.lineBreakMode = .byTruncatingTail
        f.usesSingleLineMode = true
        return f
    }

    func updateNSView(_ f: Field, context: Context) { context.coordinator.parent = self }
}

struct FileIcon: View {
    let kind: FileKind

    var body: some View {
        if let symbol = kind.symbol {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(tint).frame(width: 16, height: 16)
        } else {
            TypstGlyph().stroke(.teal, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)).frame(width: 13, height: 13).frame(width: 16, height: 16)
        }
    }

    private var tint: Color {
        switch kind {
        case .folder: .blue
        case .pdf: .red
        case .bib, .package: .brown
        default: .secondary
        }
    }
}

/// A lowercase "t" drawn from strokes: our own mark, not the Typst logo.
struct TypstGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        var path = Path()
        path.move(to: p(0.42, 0.06))
        path.addLine(to: p(0.42, 0.72))
        path.addQuadCurve(to: p(0.72, 0.9), control: p(0.42, 0.9))
        path.move(to: p(0.14, 0.32))
        path.addLine(to: p(0.74, 0.32))
        return path
    }
}

/// Quick Look for PDFs, images and anything else the editor cannot open.
struct QuickLookView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let v = QLPreviewView(frame: .zero, style: .normal)!
        v.previewItem = url as NSURL
        return v
    }

    func updateNSView(_ v: QLPreviewView, context: Context) {
        if (v.previewItem as? NSURL) as URL? != url { v.previewItem = url as NSURL }
    }
}

// MARK: Search

/// Xcode's Find navigator: a "Find › Text › Containing" path of pull-down menus, a native search field with a
/// case pop-up, a result summary, and hits grouped under disclosable files. Replace adds a "With" field, a
/// strike-through preview in every row, and Replace / Replace All.
private struct SearchTab: View {
    @AppStorage(SettingsKey.findDetail) private var detail = 1
    let project: Project
    let model: SidebarModel
    @State private var collapsed: Set<RelPath> = []
    @State private var selection: Set<SearchHit.ID> = []
    @State private var focusRequest = 0
    /// Bumped after a replace so the search runs again on the edited text.
    @State private var rerun = 0
    @State private var replacing = false
    @State private var replaceError: String?

    private struct Key: Equatable { var query: String; var options: SearchOptions; var files: Int; var rerun: Int }

    private enum Matching: Hashable { case containing, word, regex }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            // Scrolls when the fixed-size menus are wider than the column: the TabView sizes to its widest tab and clipped every tab on the left.
            ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                pathMenu(model.searchReplaces ? "Replace" : "Find", selection: $model.searchReplaces) {
                    Text("Find").tag(false)
                    Text("Replace").tag(true)
                }
                separator
                pathMenu(model.searchShowsReferences ? "References" : "Text", selection: $model.searchShowsReferences) {
                    Text("Text").tag(false)
                    Text("References").tag(true).disabled(model.searchReplaces)
                }
                if !model.searchShowsReferences {
                    separator
                    pathMenu(title(of: matching), selection: matchingBinding) {
                        Text("Containing").tag(Matching.containing)
                        Text("Matching Word").tag(Matching.word)
                        Text("Regular Expression").tag(Matching.regex)
                    }
                }
            }
            .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 2)
            }
            if model.searchShowsReferences {
                ReferencesResults(project: project)
            } else {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        NativeSearchField(text: $model.searchQuery, prompt: model.searchOptions.regex ? "Regular Expression" : "Text",
                                          focusRequest: focusRequest)
                        pathMenu(model.searchOptions.caseSensitive ? "Matching Case" : "Ignoring Case",
                                 selection: $model.searchOptions.caseSensitive) {
                            Text("Ignoring Case").tag(false)
                            Text("Matching Case").tag(true)
                        }
                    }
                    if model.searchReplaces {
                        TextField("With", text: $model.replaceText, prompt: Text(model.searchOptions.regex ? "With ($1 for groups)" : "With"))
                            .textFieldStyle(.roundedBorder)
                        HStack(spacing: 6) {
                            if replacing { ProgressView().controlSize(.small) }
                            Spacer(minLength: 0)
                            Button("Replace") { replace(selectedHits) }
                                .disabled(replacing || selectedHits.isEmpty)
                                .help("Replace the selected results")
                            Button("Replace All") { replace(nil) }
                                .disabled(replacing || (model.searchOutcome?.files.isEmpty ?? true))
                                .help("Replace every match in the project")
                        }
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                results
            }
        }
        .onAppear { focusRequest += 1 }
        .onChange(of: model.searchShowsReferences) { if !model.searchShowsReferences { focusRequest += 1 } }
        .onChange(of: model.searchReplaces) { if model.searchReplaces { model.searchShowsReferences = false } }
        .task(id: Key(query: model.searchQuery, options: model.searchOptions, files: project.fileRevision, rerun: rerun)) {
            guard !model.searchQuery.isEmpty else { model.searchOutcome = nil; _ = await project.search("", options: model.searchOptions); return }
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            if let outcome = await project.search(model.searchQuery, options: model.searchOptions) { model.searchOutcome = outcome }
        }
        .onChange(of: selection) {
            guard selection.count == 1, let hit = selectedHits.first else { return }
            project.reveal(hit)
        }
        .alert("Replace Failed", isPresented: Binding(get: { replaceError != nil }, set: { if !$0 { replaceError = nil } })) {
            Button("OK") {}
        } message: {
            Text(replaceError ?? "")
        }
    }

    private var separator: some View { Image(systemName: "chevron.compact.right").foregroundStyle(.tertiary) }

    private var selectedHits: [SearchHit] {
        model.searchOutcome?.files.flatMap(\.hits).filter { selection.contains($0.id) } ?? []
    }

    /// Nil replaces every match, including any past the result list's limit.
    private func replace(_ hits: [SearchHit]?) {
        replacing = true
        Task {
            defer { replacing = false; selection = []; rerun += 1 }
            do {
                _ = try await project.replace(model.searchQuery, options: model.searchOptions, with: model.replaceText, only: hits)
            } catch {
                replaceError = error.localizedDescription
            }
        }
    }

    @ViewBuilder private var results: some View {
        if let o = model.searchOutcome {
            if let error = o.error {
                ContentUnavailableView("Invalid Expression", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if o.files.isEmpty {
                ContentUnavailableView.search(text: model.searchQuery)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text(summary(o)).font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 12).padding(.bottom, 4)
                    List(selection: $selection) {
                        ForEach(o.files) { f in
                            DisclosureGroup(isExpanded: expanded(f.id)) {
                                ForEach(f.hits) { h in hitRow(h).tag(h.id) }
                            } label: {
                                fileRow(f).selectionDisabled()
                            }
                        }
                    }
                }
            }
        } else {
            Color.clear
        }
    }

    private func fileRow(_ f: SearchFileResult) -> some View {
        HStack(spacing: 5) {
            FileIcon(kind: FileKind(path: f.id.raw))
            Text(f.id.name).fontWeight(.semibold).lineLimit(1)
            if let parent = f.id.parent {
                Text(parent.raw).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
        }
        .badge(f.hits.count)
        .help(f.id.raw)
    }

    private func hitRow(_ h: SearchHit) -> some View {
        Text(highlighted(h)).font(.system(size: 12)).lineLimit(lines: detail)
            .help("Line \(h.line)")
            .accessibilityLabel("Line \(h.line): \(h.context)")
    }

    private func summary(_ o: SearchOutcome) -> String {
        let results = o.matchCount == 1 ? "1 result" : "\(o.matchCount) results"
        let files = o.files.count == 1 ? "1 file" : "\(o.files.count) files"
        return o.truncated ? "First \(results) in \(files)" : "\(results) in \(files)"
    }

    private func expanded(_ file: RelPath) -> Binding<Bool> {
        Binding(get: { !collapsed.contains(file) },
                set: { if $0 { collapsed.remove(file) } else { collapsed.insert(file) } })
    }

    private var matching: Matching {
        model.searchOptions.regex ? .regex : model.searchOptions.wholeWord ? .word : .containing
    }

    private var matchingBinding: Binding<Matching> {
        Binding(get: { matching }, set: {
            model.searchOptions.regex = $0 == .regex
            model.searchOptions.wholeWord = $0 == .word
        })
    }

    private func title(of m: Matching) -> String {
        switch m {
        case .containing: "Containing"
        case .word: "Matching Word"
        case .regex: "Regular Expression"
        }
    }

    /// A borderless pull-down showing its current value, like the segments of Xcode's find path.
    private func pathMenu<V: Hashable, Items: View>(_ title: String, selection: Binding<V>, @ViewBuilder items: () -> Items) -> some View {
        Menu {
            Picker(title, selection: selection, content: items).pickerStyle(.inline).labelsHidden()
        } label: {
            Text(title)
        }
        .menuStyle(.button).buttonStyle(.accessoryBar)
        .controlSize(.small).fixedSize()
    }

    /// The line with leading indentation dropped and, when the match sits far right, the start elided so it stays
    /// visible. In Replace mode the match is struck through and followed by what it becomes, as in Xcode.
    private func highlighted(_ h: SearchHit) -> AttributedString {
        let ns = h.context as NSString
        var start = 0
        while start < h.contextMatch.location, let s = UnicodeScalar(ns.character(at: start)), CharacterSet.whitespaces.contains(s) { start += 1 }
        var elided = false
        if h.contextMatch.location - start > 24 {
            start = ns.rangeOfComposedCharacterSequence(at: h.contextMatch.location - 16).location
            elided = true
        }
        let match = NSRange(location: h.contextMatch.location - start, length: h.contextMatch.length)
        let shown = ns.substring(from: start) as NSString
        var a = AttributedString(elided ? "…" : "")
        a += AttributedString(shown.substring(to: match.location))
        var hit = AttributedString(shown.substring(with: match))
        hit.font = .system(size: 12, weight: .bold)
        if model.searchReplaces {
            hit.strikethroughStyle = .single
            hit.backgroundColor = .red.opacity(0.2)
            var new = AttributedString(h.replacement(query: model.searchQuery, options: model.searchOptions, template: model.replaceText))
            new.font = .system(size: 12, weight: .bold)
            new.backgroundColor = .green.opacity(0.25)
            a += hit + new
        } else {
            hit.backgroundColor = .yellow.opacity(0.35)
            a += hit
        }
        a += AttributedString(shown.substring(from: NSMaxRange(match)))
        return a
    }
}

/// `NSSearchField`, for the native rounded look with magnifying glass and clear button.
private struct NativeSearchField: NSViewRepresentable {
    @Binding var text: String
    let prompt: String
    /// Bumped by the caller to move keyboard focus into the field.
    let focusRequest: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSearchField {
        let f = NSSearchField()
        f.delegate = context.coordinator
        f.target = context.coordinator
        f.action = #selector(Coordinator.changed(_:))
        f.sendsSearchStringImmediately = true
        f.focusRingType = .default
        return f
    }

    func updateNSView(_ f: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if f.stringValue != text { f.stringValue = text }
        f.placeholderString = prompt
        if context.coordinator.focused != focusRequest {
            context.coordinator.focused = focusRequest
            DispatchQueue.main.async { f.window?.makeFirstResponder(f) }
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: NativeSearchField
        var focused = 0
        init(_ parent: NativeSearchField) { self.parent = parent }

        /// Typing and the clear button.
        @MainActor @objc func changed(_ sender: NSSearchField) {
            if parent.text != sender.stringValue { parent.text = sender.stringValue }
        }

        func controlTextDidChange(_ note: Notification) {
            if let f = note.object as? NSSearchField { changed(f) }
        }
    }
}

// MARK: Outline

private struct OutlineNode: Identifiable {
    let item: OutlineItem
    var children: [OutlineNode]?
    var id: Int { item.id }

    static func tree(_ items: [OutlineItem]) -> [OutlineNode] {
        func build(_ i: inout Int, above level: Int) -> [OutlineNode] {
            var out: [OutlineNode] = []
            while i < items.count, items[i].level > level {
                let item = items[i]
                i += 1
                let kids = build(&i, above: item.level)
                out.append(OutlineNode(item: item, children: kids.isEmpty ? nil : kids))
            }
            return out
        }
        var i = 0
        return build(&i, above: 0)
    }
}

private struct OutlineTab: View {
    let project: Project
    /// The row being dragged; drops read it instead of loading the item provider.
    @State private var dragging: OutlineItem?
    @State private var indicator: (id: Int, drop: SectionDrop)?
    @State private var refusal: String?

    var body: some View {
        let items = project.outline
        if items.isEmpty {
            ContentUnavailableView("No Headings", systemImage: "list.bullet.indent")
        } else {
            let unused = project.unreferencedLabelHeadings(items)
            let broken = project.brokenReferences
            VStack(spacing: 0) {
                if !broken.isEmpty || !unused.isEmpty { header(broken: broken, unused: unused.count) }
                List(OutlineNode.tree(items), children: \.children) { node in
                    row(node.item, unused: unused.contains(node.id))
                }
            }
            .alert("Can't Move Section", isPresented: Binding { refusal != nil } set: { if !$0 { refusal = nil } }) {
                Button("OK") { refusal = nil }
            } message: { Text(refusal ?? "") }
        }
    }

    private func header(broken: [Diagnostic], unused: Int) -> some View {
        HStack(spacing: 10) {
            if let first = broken.first {
                Button { project.reveal(first) } label: {
                    Label("\(broken.count) broken reference\(broken.count == 1 ? "" : "s")", systemImage: "exclamationmark.triangle.fill")
                }
                .buttonStyle(.plain).foregroundStyle(.orange)
                .help("References to a label or bibliography key that does not exist; click to show the first")
            }
            if unused > 0 {
                Label("\(unused) unused label\(unused == 1 ? "" : "s")", systemImage: "circle.fill").foregroundStyle(.secondary)
                    .help("Headings whose label is never referenced")
            }
            Spacer(minLength: 0)
        }
        .font(.caption).labelStyle(.titleAndIcon).imageScale(.small)
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private func row(_ item: OutlineItem, unused: Bool) -> some View {
        RowButton { project.reveal(item) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if !item.numbering.isEmpty { Text(item.numbering).foregroundStyle(.secondary).monospacedDigit() }
                Text(item.title.isEmpty ? "Untitled" : item.title).lineLimit(1)
                if unused {
                    Circle().fill(.tertiary).frame(width: 6, height: 6)
                        .help("Its label is never referenced").accessibilityLabel("Unused label")
                }
                Spacer(minLength: 4)
                Text("\(item.page + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .onDrag {
            dragging = item
            return NSItemProvider(object: SectionDropTarget.payload(item) as NSString)
        }
        .modifier(SectionDropTarget(item: item, dragging: $dragging, indicator: $indicator) { from, drop, adopt in
            Task { if let message = await project.moveSection(from, drop, item, adoptLevel: adopt) { refusal = message } }
        })
        .overlay(alignment: indicator?.drop == .before ? .top : .bottom) {
            if indicator?.id == item.id { Rectangle().fill(.tint).frame(height: 2).allowsHitTesting(false) }
        }
    }
}

/// Drops on an outline row: the upper half inserts before its section, the lower half after it; ⌥ adopts its level.
private struct SectionDropTarget: ViewModifier {
    let item: OutlineItem
    @Binding var dragging: OutlineItem?
    @Binding var indicator: (id: Int, drop: SectionDrop)?
    let perform: @MainActor (OutlineItem, SectionDrop, Bool) -> Void
    @State private var height: CGFloat = 0

    /// `dragging` outlives a drag cancelled elsewhere, so a drop only counts when its payload names that row.
    nonisolated static func payload(_ item: OutlineItem) -> String { "tympan-outline-section:\(item.id)" }

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .onDrop(of: [.plainText], delegate: Delegate(target: self))
    }

    struct Delegate: DropDelegate {
        let target: SectionDropTarget
        func place(_ info: DropInfo) -> SectionDrop { info.location.y < target.height / 2 ? .before : .after }
        func validateDrop(info: DropInfo) -> Bool { target.dragging != nil }
        func dropUpdated(info: DropInfo) -> DropProposal? {
            target.indicator = (target.item.id, place(info))
            return DropProposal(operation: .move)
        }
        func dropExited(info: DropInfo) { if target.indicator?.id == target.item.id { target.indicator = nil } }
        func performDrop(info: DropInfo) -> Bool {
            target.indicator = nil
            guard let from = target.dragging, let provider = info.itemProviders(for: [.plainText]).first else { return false }
            target.dragging = nil
            let drop = place(info), adopt = NSEvent.modifierFlags.contains(.option), perform = target.perform
            _ = provider.loadObject(ofClass: NSString.self) { s, _ in
                let ok = (s as? NSString).map(String.init) == SectionDropTarget.payload(from)
                Task { @MainActor in if ok { perform(from, drop, adopt) } }
            }
            return true
        }
    }
}

// MARK: Symbols

struct SymbolsTab: View {
    let model: SidebarModel
    let tables: TableEditing
    let enabled: Bool

    var body: some View {
        @Bindable var model = model
        let shown = SymbolCatalog.filter(SymbolCatalog.all, query: model.symbolQuery, recent: model.recents.ids)
        VStack(spacing: 0) {
            TextField("Search Symbols", text: $model.symbolQuery).textFieldStyle(.roundedBorder).padding(8)
            if shown.isEmpty {
                ContentUnavailableView.search(text: model.symbolQuery)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 38), spacing: 4)], spacing: 4) {
                        ForEach(shown) { s in
                            Button { insert(s) } label: {
                                Text(s.text).font(.system(size: 20))
                                    .frame(maxWidth: .infinity, minHeight: 34)
                                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .help(s.id)
                            .accessibilityLabel(s.name)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .disabled(!enabled)
            }
        }
    }

    private func insert(_ s: TypstSymbol) {
        tables.editor?.insertText { SymbolCatalog.insertion(for: s, mode: $0) }
        model.recents.use(s)
    }
}

// MARK: References

struct ReferencesTab: View {
    let project: Project
    let model: SidebarModel
    let tables: TableEditing
    let enabled: Bool
    @State private var adding = false

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Text("Bibliography").font(.headline).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    TextField("Search entries", text: $model.referenceQuery).glassSearchField().frame(maxWidth: 170)
                    Button("Add Reference…", systemImage: "plus") { adding = true }
                        .labelStyle(.iconOnly).buttonStyle(.glass).buttonBorderShape(.circle)
                        .help("Add Reference…")
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            Divider()
            if model.bibFiles.isEmpty {
                ContentUnavailableView {
                    Label("No Bibliography", systemImage: "books.vertical")
                } description: {
                    Text("Add a .bib or hayagriva .yml file to the project.")
                } actions: {
                    Button("Add Reference…") { adding = true }.buttonStyle(.glass)
                }
            } else {
                List {
                    ForEach(model.bibFiles) { f in
                        let entries = filtered(f.entries)
                        if f.error != nil || !entries.isEmpty {
                            Section(f.id.raw) {
                                if let error = f.error {
                                    Label(error, systemImage: "xmark.octagon.fill").foregroundStyle(.red).font(.callout).textSelection(.enabled)
                                }
                                ForEach(entries) { e in
                                    Button { cite(e) } label: { BibEntryRow(entry: e) }.buttonStyle(.plain).disabled(!enabled)
                                }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .sheet(isPresented: $adding) { AddReferenceSheet(project: project, tables: tables) }
        .task(id: project.bibliographyRevision) {
            if !model.bibFiles.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
            guard !Task.isCancelled else { return }
            model.bibFiles = await project.references()
        }
    }

    private func filtered(_ entries: [BibEntry]) -> [BibEntry] {
        entries.filter { $0.matches(model.referenceQuery) }
    }

    private func cite(_ e: BibEntry) {
        tables.editor?.insertText { BibliographyFile.citation(e.key, mode: $0) }
    }
}

/// One bibliography entry as the References popover and the citation picker show it: bold key with a tinted type
/// badge, the title, then "authors · year".
struct BibEntryRow: View {
    let entry: BibEntry
    /// The key of the earlier entry this one repeats, in the .bib form.
    var duplicateOf: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(entry.key).font(.system(size: 13, weight: .bold, design: .monospaced))
                if !entry.kind.isEmpty { KindBadge(kind: entry.kind.lowercased()) }
                if let duplicateOf {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        .help("Duplicate of \(duplicateOf)")
                        .accessibilityLabel("Duplicate of \(duplicateOf)")
                }
            }
            if !entry.title.isEmpty { Text(entry.title).lineLimit(2) }
            let byline = [entry.authors, entry.year.map(String.init) ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
            if !byline.isEmpty { Text(byline).font(.callout).foregroundStyle(.secondary).lineLimit(1) }
        }
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct KindBadge: View {
    let kind: String

    var body: some View {
        Text(kind)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(tint.opacity(0.15), in: .capsule)
            .background(.background.opacity(0.9), in: .capsule)     // stays legible on a selected row
    }

    private var tint: Color {
        switch kind {
        case "book", "inbook", "incollection", "booklet", "anthology", "chapter": .purple
        case "article", "periodical", "newspaper": .blue
        case "inproceedings", "proceedings", "conference": .orange
        case "thesis", "phdthesis", "mastersthesis": .green
        case "online", "web", "blog", "software": .teal
        case "report", "techreport", "manual": .brown
        default: .gray
        }
    }
}
