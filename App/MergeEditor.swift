import SwiftUI
import TypoKit
import TypstEngine

/// Side-by-side resolution of a conflicted file: one choice per block, then Apply writes the result through the buffer.
struct MergeEditorSheet: View {
    typealias Choice = ConflictRegion.Choice

    let project: Project
    let model: GitModel
    let change: GitChange
    @Environment(\.dismiss) private var dismiss
    @State private var text: String?
    @State private var choices: [Choice?] = []
    @State private var showResult = false
    @State private var loadError: String?

    private static let keptContext = 3                  // lines shown at each end of a long unchanged stretch
    private var segments: [MergeSegment] { ConflictRegion.segments(text ?? "") }
    private var blocks: [ConflictRegion] { ConflictRegion.parse(text ?? "") }
    private var resolvedCount: Int { choices.compactMap { $0 }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(12)
            Divider()
            if let loadError {
                Text(loadError).foregroundStyle(.red).padding(12)
                Spacer(minLength: 0)
            } else if text == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if blocks.isEmpty {
                Text("This file has no conflict markers, for example because one side deleted it. Close this and use “Keep Mine” or “Keep Theirs” in the file’s context menu.")
                    .foregroundStyle(.secondary).padding(12)
                Spacer(minLength: 0)
            } else {
                columnTitles.padding(.horizontal, 12).padding(.vertical, 6)
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(segments.enumerated()), id: \.offset) { _, s in
                            switch s {
                            case .context(let lines): context(lines)
                            case .conflict(let i, let r): conflict(i, r)
                            }
                        }
                    }
                    .padding(12)
                }
                Divider()
                DisclosureGroup("Result", isExpanded: $showResult) {
                    ScrollView {
                        Text(ConflictRegion.resolve(text ?? "", choices: choices))
                            .font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 140)
                }
                .padding(12)
            }
            Divider()
            HStack {
                Spacer()
                SheetButtons(ok: resolvedCount == blocks.count ? "Apply" : "Apply \(resolvedCount) of \(blocks.count)",
                             disabled: resolvedCount == 0 || model.busy, cancel: { dismiss() }, action: apply)
                    .accessibilityHint("Writes the chosen sides into the file")
            }
            .padding(12)
        }
        .frame(minWidth: 760, idealWidth: 900, minHeight: 520, idealHeight: 640)
        .task { await load() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(change.path).font(.headline).lineLimit(1).truncationMode(.middle)
            Text("\(resolvedCount) of \(blocks.count) conflicts resolved").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("All Ours") { choices = blocks.map { _ in .mine } }
                .accessibilityLabel("Use ours for every conflict")
            Button("All Theirs") { choices = blocks.map { _ in .theirs } }
                .accessibilityLabel("Use theirs for every conflict")
        }
        .disabled(blocks.isEmpty)
    }

    private var columnTitles: some View {
        HStack(spacing: 12) {
            Text(blocks.first.map(\.mineLabel).flatMap { $0.isEmpty ? nil : $0 } ?? "Ours").frame(maxWidth: .infinity, alignment: .leading)
            Text(blocks.first.map(\.theirsLabel).flatMap { $0.isEmpty ? nil : $0 } ?? "Theirs").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption.bold()).foregroundStyle(.secondary)
    }

    private func context(_ lines: [String]) -> some View {
        let long = lines.count > 2 * Self.keptContext + 1
        let shown = long ? Array(lines.prefix(Self.keptContext)) + Array(lines.suffix(Self.keptContext)) : lines
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(shown.prefix(long ? Self.keptContext : shown.count).enumerated()), id: \.offset) { code($1) }
            if long {
                Text("… \(lines.count - 2 * Self.keptContext) unchanged lines").font(.caption).foregroundStyle(.tertiary).padding(.vertical, 2)
                ForEach(Array(shown.suffix(Self.keptContext).enumerated()), id: \.offset) { code($1) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func code(_ line: String) -> some View {
        Text(line.isEmpty ? " " : line).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
    }

    private func conflict(_ i: Int, _ r: ConflictRegion) -> some View {
        let c = i < choices.count ? choices[i] : nil
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                pick("Use Ours", .mine, i)
                pick("Use Theirs", .theirs, i)
                pick("Use Both", .both, i)
                Text("Conflict \(i + 1)").font(.caption).foregroundStyle(.secondary)
            }
            .controlSize(.small)
            HStack(alignment: .top, spacing: 12) {
                side(r.mine, on: c == .mine || c == .both, dimmed: c == .theirs)
                side(r.theirs, on: c == .theirs || c == .both, dimmed: c == .mine)
            }
        }
    }

    /// Choosing the active button again takes the choice back.
    private func pick(_ title: String, _ choice: Choice, _ i: Int) -> some View {
        let on = i < choices.count && choices[i] == choice
        return Button(title) { choices[i] = on ? nil : choice }
            .buttonStyle(.bordered).tint(on ? .accentColor : nil)
            .accessibilityLabel("\(title) for conflict \(i + 1)")
            .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func side(_ lines: [String], on: Bool, dimmed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if lines.isEmpty { Text("(empty)").font(.caption).foregroundStyle(.tertiary) }
            ForEach(Array(lines.enumerated()), id: \.offset) { code($1) }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(on ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        .opacity(dimmed ? 0.4 : 1)
    }

    private func load() async {
        await project.reloadChangedFiles()              // git rewrote the file outside the buffer
        guard let p = RelPath(change.path) else { loadError = "Invalid path"; return }
        do {
            text = try await project.open(p).storage.string
            choices = Array(repeating: nil, count: ConflictRegion.parse(text ?? "").count)
        } catch { loadError = "Couldn’t open “\(change.path)”." }
    }

    private func apply() {
        guard let p = RelPath(change.path), let text else { return }
        let resolved = ConflictRegion.resolve(text, choices: choices)
        let complete = resolvedCount == blocks.count
        let change = change
        dismiss()
        Task {
            await model.run(project, "Couldn’t Resolve “\(change.path)”") {
                let length = (try await project.open(p)).storage.length
                try await project.edit(p, [Replacement(range: NSRange(location: 0, length: length), text: resolved)], actionName: "Resolve Conflicts")
                if complete { try await project.stage([change]) } else { try await project.saveAll() }
            }
        }
    }
}
