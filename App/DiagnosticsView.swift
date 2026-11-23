import SwiftUI
import TypoKit
import TypstEngine

struct DiagnosticsView: View {
    let project: Project
    @State private var todos: [TodoItem] = []
    @State private var todoCache: [RelPath: TodoCacheEntry] = [:]
    @AppStorage(SettingsKey.issueDetail) private var detail = 0

    var body: some View {
        let diagnostics = project.diagnostics
        let hints = project.lintHints
        List {
            Section {
                if diagnostics.isEmpty {
                    Label("No Issues", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                }
                ForEach(diagnostics) { d in IssueRow(project: project, diagnostic: d) }
            }
            if !hints.isEmpty {
                Section("Hints") {
                    ForEach(hints) { h in
                        HStack(alignment: .top, spacing: 4) {
                            RowButton { project.reveal(h) } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(h.message).lineLimit(lines: detail)
                                        Text(IssueRow(project: project, diagnostic: h).place).font(.system(size: 10)).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            if QuickFixes.mayFix(h) {
                                Button { QuickFixMenu.show(for: h, project: project) } label: { Image(systemName: "lightbulb.fill").foregroundStyle(.yellow) }
                                    .buttonStyle(.borderless).help("Quick Fixes")
                            }
                        }
                    }
                }
            }
            Section("TODOs") {
                if todos.isEmpty { Text("No TODOs").foregroundStyle(.tertiary) }
                ForEach(todos) { t in
                    RowButton { project.show(t.file, range: t.range, flash: true) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.text.isEmpty ? t.marker : "\(t.marker) \(t.text)").lineLimit(lines: detail)
                            Text("\(t.file.raw):\(t.line)").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        // A compile follows every edit, so the status change is the edit trigger; the sleep coalesces bursts.
        .task(id: TodoKey(files: project.fileRevision, status: project.status)) {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            let r = await project.todos(cache: todoCache)
            guard !Task.isCancelled else { return }
            todos = r.items
            todoCache = r.cache
        }
    }

    private struct TodoKey: Equatable { let files: Int; let status: CompileStatus }
}

/// One compiler diagnostic: severity icon, message, file:line, and the quick-fix lightbulb. Shared by the Issues
/// navigator and the bottom area.
struct IssueRow: View {
    let project: Project
    let diagnostic: Diagnostic
    @AppStorage(SettingsKey.issueDetail) private var detail = 0

    var body: some View {
        let d = diagnostic
        HStack(alignment: .top, spacing: 4) {
            RowButton { project.reveal(d) } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: d.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(d.severity == .error ? .red : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.message).lineLimit(lines: detail)
                        Text(place).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }
            if QuickFixes.mayFix(d) {
                Button { QuickFixMenu.show(for: d, project: project) } label: { Image(systemName: "lightbulb.fill").foregroundStyle(.yellow) }
                    .buttonStyle(.borderless).help("Quick Fixes")
            }
        }
    }

    // shortcut: no line number for a file that has not been opened (a buffer holds the text to count in).
    var place: String {
        switch diagnostic.origin {
        case .project(let loc):
            guard let text = project.buffer(for: loc.file)?.storage.string as NSString?, loc.range.location <= text.length else { return loc.file.raw }
            var line = 1
            for i in 0..<loc.range.location where text.character(at: i) == 10 { line += 1 }
            return "\(loc.file.raw):\(line)"
        case .package(let spec): return spec
        case .detached: return ""
        }
    }
}

extension SettingsKey {
    static let lintHints = "showLintHints"
}
