import AppKit
import SwiftUI
import TypoKit
import TypstEngine

/// What the floating search field does: Open Quickly (⇧⌘O, ⌘T) or Go to Line (⌘L).
enum QuickOpenMode { case files, line }

/// The panel's state; the panel's key handling drives the selection, since the field editor swallows the arrow keys.
@MainActor @Observable final class QuickOpenModel {
    let mode: QuickOpenMode
    var query = "" { didSet { refresh() } }
    var items: [QuickOpenItem] = [] { didSet { refresh() } }
    /// The results chosen before, most recent first (`QuickOpenRecents`).
    var recent: [QuickOpenItem.Identity] = [] { didSet { refresh() } }
    /// The open files, listed after the recents while the field is empty.
    var openFiles: [RelPath] = [] { didSet { refresh() } }
    private(set) var results: [QuickOpenResult] = []
    /// What the list shows: the results, with the alternates of the `expanded` ones under them.
    private(set) var rows: [QuickOpenLine] = []
    private var expanded: Set<Int> = []
    /// Index into `rows`.
    var selection = 0
    /// Opens a result; `true` for ⌥Return.
    @ObservationIgnored var open: (QuickOpenResult, Bool) -> Void = { _, _ in }
    /// Forgets the stored recents.
    @ObservationIgnored var forgetRecents: () -> Void = {}
    /// Go to Line's Return; false keeps the panel open (the input is no line).
    @ObservationIgnored var goToLine: (String) -> Bool = { _ in false }
    @ObservationIgnored var onResultsChange: () -> Void = {}

    init(mode: QuickOpenMode) { self.mode = mode }

    /// The field is empty: the list holds the recent results.
    var showsRecents: Bool { mode == .files && query.trimmingCharacters(in: .whitespaces).isEmpty && !results.isEmpty }

    private func refresh() {
        guard mode == .files else { return }
        results = QuickOpen.results(query, items: items, recent: recent, open: openFiles)
        expanded = []
        rows = QuickOpen.rows(results, expanded: expanded)
        selection = 0
        onResultsChange()
    }

    func result(_ row: QuickOpenLine) -> QuickOpenResult { row.alternate.map(results[row.result].alternate) ?? results[row.result] }

    func step(_ d: Int) { if !rows.isEmpty { selection = min(max(selection + d, 0), rows.count - 1) } }

    func clearRecents() {
        forgetRecents()
        recent = []
        openFiles = []
    }

    /// Shows or hides the alternates of result `i` and selects it.
    func toggle(_ i: Int) {
        if expanded.remove(i) == nil { expanded.insert(i) }
        rows = QuickOpen.rows(results, expanded: expanded)
        selection = rows.firstIndex { $0.result == i && $0.alternate == nil } ?? 0
        onResultsChange()
    }

    /// → on a result with hidden alternates shows them; false leaves the key to the field.
    func expandSelected() -> Bool {
        guard rows.indices.contains(selection), rows[selection].alternate == nil, !expanded.contains(rows[selection].result),
              !results[rows[selection].result].alternates.isEmpty else { return false }
        toggle(rows[selection].result)
        return true
    }

    /// ← on an expanded result or one of its alternates hides them; false leaves the key to the field.
    func collapseSelected() -> Bool {
        guard rows.indices.contains(selection), expanded.contains(rows[selection].result) else { return false }
        toggle(rows[selection].result)
        return true
    }

    func activate(alternate: Bool) {
        switch mode {
        case .line: if !goToLine(query) { NSSound.beep() }
        case .files: if rows.indices.contains(selection) { open(result(rows[selection]), alternate) } else { NSSound.beep() }
        }
    }
}

/// Xcode's Open Quickly look: a large rounded search field near the top of the window; results grow it downward.
struct QuickOpenView: View {
    @Bindable var model: QuickOpenModel
    let projectName: String
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.system(size: 20)).foregroundStyle(.secondary)
                TextField(model.mode == .files ? "Open Quickly" : "Line Number", text: $model.query)
                    .textFieldStyle(.plain).font(.system(size: 22))
                    .focused($focused)
            }
            .padding(.horizontal, 20)
            .frame(height: QuickOpenPanel.fieldHeight)
            if !model.results.isEmpty {
                Divider().padding(.horizontal, 12)
                if model.showsRecents {
                    HStack {
                        Text("Recent Results").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear Recents") { model.clearRecents() }.buttonStyle(.link).font(.system(size: 11))
                    }
                    .padding(.horizontal, 20)
                    .frame(height: QuickOpenPanel.headerHeight)
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(model.rows.enumerated()), id: \.offset) { i, row in
                                let r = model.result(row)
                                QuickOpenRow(result: r, selected: i == model.selection, projectName: projectName, child: row.alternate != nil,
                                             expanded: row.alternate == nil && model.rows.contains { $0.result == row.result && $0.alternate != nil },
                                             onBadge: r.alternates.isEmpty || row.alternate != nil ? nil : { model.toggle(row.result) }).id(i)
                                    .onTapGesture { model.selection = i; model.activate(alternate: NSEvent.modifierFlags.contains(.option)) }
                            }
                        }
                        .padding(QuickOpenPanel.listPadding)
                    }
                    .onChange(of: model.selection) { _, i in proxy.scrollTo(i) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial, in: .rect(cornerRadius: QuickOpenPanel.fieldHeight / 2))
        .overlay(RoundedRectangle(cornerRadius: QuickOpenPanel.fieldHeight / 2).strokeBorder(.separator, lineWidth: 0.5))
        .onAppear { focused = true }
    }
}

/// One result: a 32 pt icon, the name with the matched characters in bold, the breadcrumb, and a badge. An alternate
/// (`child`) is indented under its group; clicking a group's "N Alternates" badge shows or hides them.
private struct QuickOpenRow: View {
    let result: QuickOpenResult
    let selected: Bool
    let projectName: String
    var child = false
    var expanded = false
    var onBadge: (() -> Void)? = nil

    var body: some View {
        let item = result.item
        HStack(spacing: 10) {
            if child { Spacer().frame(width: 24) }
            QuickOpenIcon(kind: item.kind, file: item.file).frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 14)).lineLimit(1)
                HStack(spacing: 4) {
                    if let f = item.file { FileIcon(kind: FileKind(path: f.raw)).scaleEffect(0.75).frame(width: 12, height: 12) }
                    else { Image(systemName: "book").font(.system(size: 9)) }
                    Text(item.detail.isEmpty ? breadcrumb : item.detail).font(.system(size: 11)).lineLimit(1).truncationMode(item.detail.isEmpty ? .head : .tail)
                }
                .foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
            }
            Spacer(minLength: 8)
            if let badge {
                let capsule = Text(badge).font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(selected ? AnyShapeStyle(.white.opacity(0.25)) : AnyShapeStyle(.quaternary), in: .capsule)
                if let onBadge {
                    Button(action: onBadge) {
                        HStack(spacing: 3) { capsule; Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .semibold)) }
                    }
                    .buttonStyle(.plain)
                    .help(expanded ? "Hide Alternates" : "Show Alternates")
                } else {
                    capsule
                }
            }
        }
        .foregroundStyle(selected ? .white : .primary)
        .padding(.horizontal, 10)
        .frame(height: QuickOpenPanel.rowHeight)
        .background(selected ? Color.accentColor : .clear, in: .rect(cornerRadius: 10))
        .contentShape(Rectangle())
    }

    private var name: AttributedString {
        let s = result.item.name
        var a = AttributedString(s)
        for r in result.matched {
            if let sr = Range(r, in: s), let ar = Range(sr, in: a) { a[ar].font = .system(size: 14, weight: .bold) }
        }
        return a
    }

    private var breadcrumb: String {
        guard let f = result.item.file else { return "Typst › Documentation" }
        let line = result.line ?? (result.item.line > 0 ? result.item.line : nil)
        return ([projectName] + f.raw.split(separator: "/").map(String.init)).joined(separator: " › ") + (line.map { ":\($0)" } ?? "")
    }

    private var badge: String? {
        if !child, !result.alternates.isEmpty { return "\(result.alternates.count) Alternate\(result.alternates.count == 1 ? "" : "s")" }
        if let line = result.line { return "Line \(line)" }
        switch result.item.kind {
        case .file: return nil
        case .heading(let level): return "Heading \(level)"
        case .label: return "Label"
        case .function: return "Function"
        case .variable: return "Variable"
        case .bibKey: return "Bibliography"
        case .builtin: return "Built-in"
        case .bookmark: return "Bookmark"
        }
    }
}

/// A file's tree icon, or a coloured letter tile per symbol kind, like Xcode's symbol glyphs.
private struct QuickOpenIcon: View {
    let kind: QuickOpenItem.Kind
    let file: RelPath?

    var body: some View {
        if let tile {
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tile.color.gradient)
                .overlay(Text(tile.letter).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.white))
                .frame(width: 28, height: 28)
        } else {
            FileIcon(kind: FileKind(path: file?.raw ?? "")).scaleEffect(1.75)
        }
    }

    private var tile: (letter: String, color: Color)? {
        switch kind {
        case .file: nil
        case .heading: ("H", .indigo)
        case .label: ("L", .orange)
        case .function: ("f", .green)
        case .variable: ("v", .teal)
        case .bibKey: ("B", .brown)
        case .builtin: ("T", .purple)
        case .bookmark: ("\u{2605}", .blue)
        }
    }
}

private final class QuickOpenKeyPanel: NSPanel {
    weak var model: QuickOpenModel?
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, let model, handle(event, model) { return }
        super.sendEvent(event)
    }

    private func handle(_ event: NSEvent, _ model: QuickOpenModel) -> Bool {
        // Input methods compose with Return and the arrows: leave them to the field while text is marked.
        if (firstResponder as? NSTextView)?.hasMarkedText() == true { return false }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.isDisjoint(with: [.command, .control]) else { return false }
        switch event.keyCode {
        case 125: model.step(1)                                              // ↓
        case 126: model.step(-1)                                             // ↑
        case 36, 76: model.activate(alternate: mods.contains(.option))      // Return, Enter, ⌥Return
        case 53: onCancel?()                                                 // Esc
        case 124: return model.expandSelected()                              // →
        case 123: return model.collapseSelected()                            // ←
        default: return false
        }
        return true
    }
}

/// The floating Open Quickly / Go to Line panel of one window, centred near its top; closes on Esc or a click elsewhere.
@MainActor final class QuickOpenPanel: NSObject, NSWindowDelegate {
    static let width: CGFloat = 640, fieldHeight: CGFloat = 56, rowHeight: CGFloat = 52, listPadding: CGFloat = 6, shownRows = 8, headerHeight: CGFloat = 26
    private var panel: QuickOpenKeyPanel?
    private weak var parent: NSWindow?
    private var onClose: (() -> Void)?

    var isOpen: Bool { panel != nil }

    func show(_ model: QuickOpenModel, projectName: String, over parent: NSWindow, onClose: @escaping () -> Void) {
        self.onClose = nil            // replacing an open panel must not report a close
        close()
        self.parent = parent
        self.onClose = onClose
        let panel = QuickOpenKeyPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.styleAsGlass()
        panel.hidesOnDeactivate = true
        panel.delegate = self
        panel.model = model
        panel.onCancel = { [weak self] in self?.close(); parent.makeKeyAndOrderFront(nil) }
        let host = NSHostingView(rootView: QuickOpenView(model: model, projectName: projectName))
        host.sizingOptions = []
        panel.contentView = host
        let top = parent.frame.maxY - parent.frame.height / 5
        let height = { Self.height(rows: model.rows.count, header: model.showsRecents) }
        panel.setFrame(NSRect(x: parent.frame.midX - Self.width / 2, y: top - height(), width: Self.width, height: height()), display: false)
        model.onResultsChange = { [weak panel] in
            guard let panel else { return }
            var f = panel.frame
            let h = height()
            guard h != f.height else { return }
            f.origin.y = f.maxY - h
            f.size.height = h
            panel.setFrame(f, display: true)
        }
        let run: (@escaping @MainActor () -> Void) -> Void = { [weak self] action in
            self?.close()
            parent.makeKeyAndOrderFront(nil)
            Task { @MainActor in action() }
        }
        let open = model.open, goToLine = model.goToLine
        model.open = { r, alt in run { open(r, alt) } }
        model.goToLine = { input in
            guard QuickOpen.lineTarget(input, current: 1) != nil else { return false }
            run { _ = goToLine(input) }
            return true
        }
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    static func height(rows: Int, header: Bool = false) -> CGFloat {
        rows == 0 ? fieldHeight : fieldHeight + 1 + (header ? headerHeight : 0) + CGFloat(min(rows, shownRows)) * rowHeight + 2 * listPadding
    }

    /// Removes the panel and tells the owner; safe to call when nothing is shown.
    func close() {
        guard let panel else { return }
        self.panel = nil
        panel.delegate = nil
        panel.orderOut(nil)
        let done = onClose
        onClose = nil
        done?()
    }

    func windowDidResignKey(_ notification: Notification) { close() }
}

#Preview("Open Quickly") {
    let model = QuickOpenModel(mode: .files)
    model.items = [QuickOpenItem(kind: .file, name: "intro.typ", file: RelPath("kapitel/intro.typ")!),
                   QuickOpenItem(kind: .heading(level: 1), name: "Introduction", file: RelPath("main.typ")!, line: 3),
                   QuickOpenItem(kind: .label, name: "intro", file: RelPath("main.typ")!, line: 3),
                   QuickOpenItem(kind: .label, name: "intro", file: RelPath("kapitel/intro.typ")!, line: 1),
                   QuickOpenItem(kind: .function, name: "intro-box", file: RelPath("lib.typ")!, line: 12),
                   QuickOpenItem(kind: .builtin, name: "int", file: nil)]
    model.query = "intro"
    return QuickOpenView(model: model, projectName: "demo")
        .frame(width: QuickOpenPanel.width, height: QuickOpenPanel.height(rows: model.results.count))
        .padding(40)
}

#Preview("Go to Line") {
    QuickOpenView(model: QuickOpenModel(mode: .line), projectName: "demo")
        .frame(width: QuickOpenPanel.width, height: QuickOpenPanel.fieldHeight)
        .padding(40)
}
