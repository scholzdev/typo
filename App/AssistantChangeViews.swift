import AppKit
import SwiftUI
import TypoKit
import UniformTypeIdentifiers
import TypoAssistant

/// One changed file of an answer, like Xcode's coding assistant: the file's icon and name with a blue "M" at the
/// trailing edge, and under it the replacement text in the editor's font, clipped to a few lines. Clicking opens the
/// file at the change. With permission "Ask" the header carries Accept and Reject instead of the "M".
struct AssistantChangeCard: View {
    enum Status: Equatable { case pending, applied, reverted, rejected, failed(String) }

    static let visibleLines = 8

    let edit: ProposedEdit
    var status: Status
    /// Accept and Reject show once the answer is complete.
    var showsButtons = true
    /// Nil when Revert is possible, else the tooltip that says why not.
    var revertBlocker: String?
    var open: () -> Void = {}
    var accept: () -> Void = {}
    var reject: () -> Void = {}
    var revert: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            switch status {
            case .failed(let why):
                Label(why, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            default:
                code.onTapGesture(perform: open)
            }
        }
        .contextMenu {
            Button("Show in Editor", action: open).disabled(status == .rejected || status == .reverted || isFailed)
            Button("Revert This Change", action: revert).disabled(status != .applied || revertBlocker != nil)
            Divider()
            Button("Copy Code") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(edit.replace, forType: .string)
            }
        }
    }

    private var isFailed: Bool { if case .failed = status { true } else { false } }
    private var fileName: String { (edit.path as NSString).lastPathComponent }

    private var header: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(nsImage: NSWorkspace.shared.icon(for: UTType(filenameExtension: (edit.path as NSString).pathExtension) ?? .plainText))
                    .resizable().frame(width: 16, height: 16)
                Text(fileName).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: open)
            .help(edit.path)
            Spacer(minLength: 8)
            switch status {
            case .applied:
                Text(edit.search.isEmpty ? "A" : "M").foregroundStyle(.blue).fontWeight(.semibold).help(edit.search.isEmpty ? "Added" : "Modified")
            case .reverted: Text("Reverted").foregroundStyle(.secondary)
            case .rejected: Text("Rejected").foregroundStyle(.secondary)
            case .failed: Text("Not applied").foregroundStyle(.orange)
            case .pending:
                if showsButtons {
                    Button("Reject", action: reject).controlSize(.small)
                    Button("Accept", action: accept).controlSize(.small).buttonStyle(.borderedProminent)
                }
            }
        }
    }

    @ViewBuilder private var code: some View {
        let lines = edit.replace.components(separatedBy: "\n")
        let clipped = lines.count > Self.visibleLines
        if edit.replace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("Removes the text").font(.callout).foregroundStyle(.secondary)
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(Self.highlighted(lines.prefix(Self.visibleLines).joined(separator: "\n"), path: edit.path))
                    .fixedSize()
                    .padding(8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            .mask {
                // The last line fades out when there is more below it.
                LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: clipped ? 0.7 : 1),
                                       .init(color: clipped ? .clear : .black, location: 1)], startPoint: .top, endPoint: .bottom)
            }
        }
    }

    /// `text` in the editor's font and theme colors.
    static func highlighted(_ text: String, path: String) -> AttributedString {
        let ns = Highlighter.attributed(text, path: path)
        var out = AttributedString()
        ns.enumerateAttributes(in: NSRange(location: 0, length: ns.length)) { attrs, range, _ in
            var piece = AttributedString(ns.attributedSubstring(from: range).string)
            if let c = attrs[.foregroundColor] as? NSColor { piece.foregroundColor = Color(nsColor: c) }
            if let f = attrs[.font] as? NSFont { piece.font = Font(f) }
            out += piece
        }
        return out
    }
}

/// "1 Change in 1 File" above the prompt, with a list of the changes and Revert for the latest answer.
struct AssistantChangesBar: View {
    struct Entry: Identifiable { let id: Int; let path: String; let preview: String }

    let entries: [Entry]
    /// Nil when Revert is possible, else the tooltip that says why not.
    var revertBlocker: String?
    var open: (Int) -> Void = { _ in }
    var revert: () -> Void = {}
    @State private var listing = false

    var body: some View {
        HStack(spacing: 8) {
            Button { listing.toggle() } label: { Image(systemName: "list.bullet") }
                .buttonStyle(.plain).accessibilityLabel("Show the changes").help("Lists the changes of the latest answer")
                .popover(isPresented: $listing, arrowEdge: .top) { list }
            Text(AssistantChangeSummary.title(changes: entries.count, files: Set(entries.map(\.path)).count)).font(.callout)
            Spacer()
            Button("Revert", action: revert).controlSize(.small).disabled(revertBlocker != nil)
                .help(revertBlocker ?? "Undoes all changes of the latest answer")
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(.quaternary.opacity(0.35))
        .overlay(alignment: .top) { Divider() }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(entries) { e in
                Button { listing = false; open(e.id) } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text((e.path as NSString).lastPathComponent).fontWeight(.semibold)
                        Text(e.preview).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain).padding(.vertical, 3)
            }
        }
        .padding(10).frame(width: 280)
    }
}

/// A soft rainbow glow around the prompt box while the assistant is answering; still with Reduce Motion.
struct AssistantGlow: View {
    var radius: CGFloat = 12
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let turn = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 5) / 5 * 360
            let gradient = AngularGradient(colors: [.blue, .purple, .pink, .orange, .blue], center: .center, angle: .degrees(turn))
            RoundedRectangle(cornerRadius: radius).strokeBorder(gradient, lineWidth: 1.5)
                .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(gradient, lineWidth: 5).blur(radius: 6).opacity(0.7) }
                .padding(-1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview("Answer with two changed files") {
    let one = ProposedEdit(path: "chapters/intro.typ", search: "old", replace: "= Introduction\n#lorem(40)\n\n#let note(body) = block(fill: luma(240), inset: 8pt, body)\n#note[Remember to cite the source.]\n== Background\nSecond-level heading\nA ninth line that fades out\nA tenth line")
    let two = ProposedEdit(path: "main.typ", search: "x", replace: "#include \"chapters/intro.typ\"")
    let new = ProposedEdit(path: "refs.bib", search: "", replace: "@book{typst, title={Typst}}")
    let bad = ProposedEdit(path: "gone.typ", search: "x", replace: "y")
    return VStack(alignment: .leading, spacing: 14) {
        Text("I moved the introduction into its own file and included it from the main file.")
        AssistantChangeCard(edit: one, status: .applied)
        AssistantChangeCard(edit: two, status: .applied, revertBlocker: "The changed text was edited since, so it cannot be reverted automatically.")
        AssistantChangeCard(edit: new, status: .pending)
        AssistantChangeCard(edit: bad, status: .failed("The text to replace was not found in gone.typ. The file may have changed since the answer."))
        AssistantChangesBar(entries: [.init(id: 0, path: one.path, preview: "= Introduction"), .init(id: 1, path: two.path, preview: two.replace)])
        RoundedRectangle(cornerRadius: 12).fill(.background.secondary).frame(height: 70).overlay { AssistantGlow() }
    }
    .padding(16)
    .frame(width: 380)
}
