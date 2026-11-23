import SwiftUI
import TypoKit
import TypoAssistant
import TypstEngine

/// Under the conversation, like Xcode's: each file the conversation changed as a collapsible section with its changed
/// lines in context, added lines green with the rainbow bar beside them, removed lines red. A line opens the file there.
struct AssistantDiffPanel: View {
    let model: AssistantModel
    @State private var collapsed: Set<String> = []

    var body: some View {
        let changes = AssistantTurns.changes(in: (model.current?.messages ?? []).filter { $0.role == .assistant })
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8, pinnedViews: .sectionHeaders) {
                    ForEach(changes) { c in
                        Section {
                            if !collapsed.contains(c.path) { body(c) }
                        } header: {
                            header(c).id(c.path)
                        }
                    }
                }
                .padding(8)
            }
            .onChange(of: model.diffFile, initial: true) { _, f in
                guard let f else { return }
                collapsed.remove(f)
                proxy.scrollTo(f, anchor: .top)
            }
        }
        .overlay { if changes.isEmpty { Text("No Changes").foregroundStyle(.secondary) } }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func header(_ c: AssistantFileChange) -> some View {
        // The chevron folds the section; the rest of the header opens the file.
        HStack(spacing: 8) {
            Button {
                if collapsed.remove(c.path) == nil { collapsed.insert(c.path) }
            } label: {
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    .rotationEffect(.degrees(collapsed.contains(c.path) ? -90 : 0))
                    .frame(width: 16, height: 16).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(collapsed.contains(c.path) ? "Expand" : "Collapse")
            Button { model.openChange(c) } label: {
              HStack(spacing: 8) {
                AssistantFileIcon(path: c.path)
                Text((c.path as NSString).lastPathComponent).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 8)
                AssistantChangeCounts(change: c)
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(c.path)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.bar, in: RoundedRectangle(cornerRadius: 10))
        .contextMenu {
            Button("Revert Changes in This File") { Task { await model.revert(c) } }
        }
    }

    private func body(_ c: AssistantFileChange) -> some View {
        let current = RelPath(c.path).flatMap(model.project.assistantText(of:))
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(c.edits.enumerated()), id: \.offset) { _, e in
                AssistantDiffHunk(rows: AssistantDiffRows.rows(e.edit, current: current)) { line in model.openFile(c.path, line: line) }
            }
        }
        .padding(.vertical, 6)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// One edit's lines; each run of added lines carries one rainbow bar.
struct AssistantDiffHunk: View {
    let rows: [AssistantDiffRows.Row]
    let open: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(run.enumerated()), id: \.offset) { _, r in row(r) }
                }
                .overlay(alignment: .leading) {
                    if run.first?.kind == .added { RainbowBar().frame(width: 5).padding(.vertical, 1).padding(.leading, 3) }
                }
            }
        }
        .font(Font(Highlighter.baseFont))
    }

    /// Consecutive rows of the same kind.
    private var runs: [[AssistantDiffRows.Row]] {
        rows.reduce(into: []) { out, r in
            if out.last?.last?.kind == r.kind { out[out.count - 1].append(r) } else { out.append([r]) }
        }
    }

    private func row(_ r: AssistantDiffRows.Row) -> some View {
        HStack(spacing: 8) {
            Text(r.line.map(String.init) ?? "").foregroundStyle(.tertiary).frame(width: 34, alignment: .trailing)
            Text(r.text.isEmpty ? " " : r.text).lineLimit(1).strikethrough(r.kind == .removed, color: .red.opacity(0.5))
            Spacer(minLength: 0)
        }
        .padding(.leading, 6).padding(.vertical, 1)
        .background(r.kind == .added ? Color.green.opacity(0.12) : r.kind == .removed ? Color.red.opacity(0.10) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { if let l = r.line { open(l) } }
    }
}
