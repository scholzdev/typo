import AppKit
import SwiftUI
import TypoKit
import TypstEngine

/// One line of the Find References list.
struct ReferenceRow: Identifiable {
    let id: Int
    let file: RelPath
    let range: NSRange
    let line: Int
    /// The trimmed line and the matched range inside it.
    let text: String
    let match: NSRange?
    let isDefinition: Bool

    /// Rows for `sites` sorted by file then position; text comes from open buffers, else from disk.
    @MainActor static func make(_ sites: [(site: RelPath, range: NSRange, isDefinition: Bool)], project: Project) -> [ReferenceRow] {
        var texts: [RelPath: NSString] = [:]
        func text(of f: RelPath) -> NSString {
            if let t = texts[f] { return t }
            let t = (project.buffer(for: f)?.storage.string ?? (try? String(contentsOf: project.url(for: f), encoding: .utf8)) ?? "") as NSString
            texts[f] = t
            return t
        }
        let sorted = sites.sorted { ($0.site.raw, $0.range.location) < ($1.site.raw, $1.range.location) }
        return sorted.enumerated().map { i, s in
            let t = text(of: s.site)
            let loc = min(s.range.location, t.length)
            let lineRange = t.lineRange(for: NSRange(location: loc, length: 0))
            let raw = t.substring(with: lineRange) as NSString
            let lead = raw.length - (raw as String).drop { $0.isWhitespace }.utf16.count
            let trimmed = (raw as String).trimmingCharacters(in: .whitespacesAndNewlines)
            let line = t.substring(to: lineRange.location).reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
            let m = NSRange(location: loc - lineRange.location - lead, length: s.range.length)
            let ok = m.location >= 0 && NSMaxRange(m) <= (trimmed as NSString).length
            return ReferenceRow(id: i, file: s.site, range: s.range, line: line, text: trimmed, match: ok ? m : nil, isDefinition: s.isDefinition)
        }
    }
}

/// The last Find References of a project, shown in the sidebar's Search tab (References mode). Per project, so
/// every window lists its own; `revealRequests` asks the sidebar to switch to it.
@MainActor @Observable final class ReferenceResults {
    private static var all: [ProjectID: ReferenceResults] = [:]
    static func of(_ project: Project) -> ReferenceResults {
        if let r = all[project.id] { return r }
        let r = ReferenceResults()
        all[project.id] = r
        return r
    }

    private(set) var title = ""
    private(set) var rows: [ReferenceRow] = []
    private(set) var revealRequests = 0

    func set(title: String, rows: [ReferenceRow]) { self.title = title; self.rows = rows }
    func reveal() { revealRequests += 1 }
}

/// The list's rows and selection; the panel's key handling moves the selection.
@MainActor @Observable final class ReferenceListModel {
    let title: String
    let rows: [ReferenceRow]
    var selected = 0

    init(title: String, rows: [ReferenceRow]) { self.title = title; self.rows = rows }

    func step(_ delta: Int) { if !rows.isEmpty { selected = min(max(selected + delta, 0), rows.count - 1) } }
}

/// A key-capable borderless panel: ↑ ↓ Return and Esc are handled here, before any view sees them.
private final class ReferenceKeyPanel: NSPanel {
    var onKey: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKey?(event) == true { return }
        super.sendEvent(event)
    }
}

/// Find References' list: a Liquid Glass panel below the caret, closed by Esc, a choice or a click elsewhere.
@MainActor final class ReferencePanel: NSObject, NSWindowDelegate {
    static let shared = ReferencePanel()
    private var panel: ReferenceKeyPanel?
    private weak var parent: NSWindow?
    private static let width: CGFloat = 480, rowHeight: CGFloat = 40, maxRows = 12

    /// `caret` is in screen coordinates; the panel goes below it, or above when the screen has no room.
    func show(title: String, rows: [ReferenceRow], caret: NSRect, in window: NSWindow, choose: @escaping (ReferenceRow) -> Void, showInSidebar: @escaping () -> Void) {
        close()
        parent = window
        let model = ReferenceListModel(title: title, rows: rows)
        let pick: (ReferenceRow) -> Void = { [weak self] row in
            self?.close()
            window.makeKeyAndOrderFront(nil)
            choose(row)
        }
        let panel = ReferenceKeyPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.styleAsGlass()
        panel.hidesOnDeactivate = true
        panel.delegate = self
        panel.onKey = { [weak self, weak model] e in
            guard let model else { return false }
            switch e.keyCode {
            case 125: model.step(1)                                                         // ↓
            case 126: model.step(-1)                                                        // ↑
            case 36, 76: if model.rows.indices.contains(model.selected) { pick(model.rows[model.selected]) }   // Return
            case 53: self?.close(); window.makeKeyAndOrderFront(nil)                        // Esc
            default: return false
            }
            return true
        }
        let glass = NSGlassEffectView()
        glass.cornerRadius = 18
        let sidebar: () -> Void = { [weak self] in
            self?.close()
            window.makeKeyAndOrderFront(nil)
            showInSidebar()
        }
        glass.contentView = NSHostingView(rootView: ReferenceListView(model: model, choose: pick, showInSidebar: sidebar))
        panel.contentView = glass
        let size = NSSize(width: Self.width, height: 44 + CGFloat(min(rows.count, Self.maxRows)) * Self.rowHeight + 10)
        let screen = (window.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        var origin = NSPoint(x: caret.minX - 16, y: caret.minY - size.height - 4)
        if origin.y < screen.minY { origin.y = caret.maxY + 4 }
        origin.x = min(max(origin.x, screen.minX), screen.maxX - size.width)
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
        window.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func close() {
        guard let panel else { return }
        self.panel = nil
        panel.delegate = nil
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) { close() }
}

struct ReferenceListView: View {
    let model: ReferenceListModel
    let choose: (ReferenceRow) -> Void
    let showInSidebar: () -> Void

    private func styled(_ r: ReferenceRow) -> AttributedString {
        var a = AttributedString(r.text)
        a.font = .system(.callout, design: .monospaced)
        if let m = r.match, let range = Range(m, in: r.text), let ar = Range(range, in: a) { a[ar].font = .system(.callout, design: .monospaced).bold() }
        return a
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(model.title).font(.headline)
                Spacer()
                Button("Show in Sidebar", systemImage: "sidebar.left", action: showInSidebar)
                    .labelStyle(.iconOnly).buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.small)
                    .help("Show these references in the sidebar")
            }
            .padding(.horizontal, 16).padding(.top, 10)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.rows) { r in row(r) }
                    }
                    .padding(.horizontal, 6)
                }
                .onChange(of: model.selected) { _, new in proxy.scrollTo(new) }   // unanimated: a held arrow key outran the animation
            }
            .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ r: ReferenceRow) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text("\(r.file.raw):\(r.line)").font(.caption).foregroundStyle(.secondary)
                if r.isDefinition {
                    Text("Definition").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
            }
            Text(styled(r)).lineLimit(1).truncationMode(.tail)
        }
        .padding(.horizontal, 10).padding(.vertical, 3)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .glassEffect(model.selected == r.id ? .regular.tint(.accentColor.opacity(0.35)) : .identity, in: .rect(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture { choose(r) }
        .onHover { if $0 { model.selected = r.id } }
    }
}

/// The Search tab's References mode: the last Find References grouped by file, like the text search results.
struct ReferencesResults: View {
    let project: Project

    var body: some View {
        let results = ReferenceResults.of(project)
        if results.rows.isEmpty {
            ContentUnavailableView("No References", systemImage: "list.bullet.rectangle",
                                   description: Text("Put the caret on a label, variable or function and choose Navigate ▸ Find References (⌃⌘R)."))
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text(results.title).font(.callout).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 6)
                List {
                    ForEach(groups(results.rows), id: \.file) { group in
                        Section("\(group.file.raw) (\(group.rows.count))") {
                            ForEach(group.rows) { r in
                                RowButton { project.show(r.file, range: r.range, flash: true) } label: {
                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                        Text("\(r.line)").font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
                                        Text(highlighted(r)).font(.system(size: 12).monospaced()).lineLimit(1)
                                        if r.isDefinition {
                                            Spacer(minLength: 4)
                                            Text("Definition").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                                                .background(.quaternary, in: Capsule())
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Rows are already sorted by file then position.
    private func groups(_ rows: [ReferenceRow]) -> [(file: RelPath, rows: [ReferenceRow])] {
        var out: [(file: RelPath, rows: [ReferenceRow])] = []
        for r in rows {
            if out.last?.file == r.file { out[out.count - 1].rows.append(r) } else { out.append((r.file, [r])) }
        }
        return out
    }

    private func highlighted(_ r: ReferenceRow) -> AttributedString {
        var a = AttributedString(r.text)
        if let m = r.match, let range = Range(m, in: r.text), let ar = Range(range, in: a) {
            a[ar].backgroundColor = .yellow.opacity(0.45)
            a[ar].foregroundColor = .black
        }
        return a
    }
}
