import AppKit
import SwiftUI
import UniformTypeIdentifiers
import TypoKit
import ACPProtocol
import TypoAssistant

/// One question and its answers, like Xcode's transcript: the user's message, the files the turn changed, the
/// answers with their tool calls, the live thinking and Working rows while it runs, and a footer when it is done.
struct AssistantTurnView: View {
    let model: AssistantModel
    let turn: AssistantTurn
    /// Shown when this turn starts a new day or session.
    let header: Date?

    var body: some View {
        let running = model.isStreaming && turn.answers.contains { $0.id == model.streamingID }
        VStack(alignment: .leading, spacing: 12) {
            if let header {
                Text(header.formatted(Calendar.current.isDateInToday(header) ? .dateTime.hour().minute() : .dateTime.day().month().year().hour().minute()))
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            if let u = turn.user { AssistantUserBubble(text: u.text, mentions: u.mentions ?? []).assistantEntrance() }
            ForEach(turn.changes) { c in AssistantFileCapsule(change: c) { model.openChange(c) }.assistantEntrance() }
            ForEach(turn.answers) { m in AssistantMessageView(model: model, message: m) }
            if running { live }
            if !running, !turn.answers.isEmpty, let last = turn.answers.last {
                AssistantTurnFooter(duration: turn.duration, files: turn.changes.count, feedback: last.feedback) { model.setFeedback(last, $0) }
                    .assistantEntrance()
            }
        }
    }

    /// Tool calls the agent still runs, then thinking or Working.
    @ViewBuilder private var live: some View {
        let shown = Set(turn.answers.flatMap { $0.toolCalls ?? [] }.map(\.call.id))
        let pending = model.liveTools.filter { !shown.contains($0.id) }
        ForEach(pending, id: \.id) { c in
            AssistantToolRow(kind: c.kind, title: c.title.isEmpty ? "Tool" : c.title, status: AssistantToolStatus(acp: c.status), detail: Self.detail(c))
                .assistantEntrance()
        }
        let current = turn.answers.last
        if let current, current.text.isEmpty, let r = current.reasoning, !r.isEmpty {
            AssistantThinkingRow(text: r).assistantEntrance()
        } else if current?.text.isEmpty != false, !pending.contains(where: { AssistantToolStatus(acp: $0.status).isRunning }) {
            AssistantWorkingRow().assistantEntrance()
        }
    }

    /// What a running call shows under its title: its command, else its text.
    static func detail(_ c: ACPToolCall) -> String? {
        if let cmd = c.rawInput?["command"]?.string { return "Running \(cmd)" }
        return c.content.compactMap { $0["content"]?["text"]?.string }.first
    }
}

/// The user's message: a wide pill with a light blue gradient.
struct AssistantUserBubble: View {
    let text: String
    /// The "@"-mentioned paths, whose file names show in grey monospace.
    var mentions: [String] = []

    var body: some View {
        Text(styled)
            .font(.system(size: 13, weight: .medium))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(LinearGradient(colors: [Color.blue.opacity(0.16), Color.blue.opacity(0.26)], startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var styled: AttributedString {
        var out = AttributedString(text)
        for r in AssistantMentions.ranges(of: mentions, in: text) {
            guard let lo = AttributedString.Index(r.lowerBound, within: out), let hi = AttributedString.Index(r.upperBound, within: out) else { continue }
            out[lo..<hi].font = .system(size: 13, design: .monospaced)
            out[lo..<hi].foregroundColor = .secondary
        }
        return out
    }
}

/// A file the turn changed: icon and name, +N / −N, and M or A; a click opens the file at its first change.
struct AssistantFileCapsule: View {
    let change: AssistantFileChange
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                AssistantFileIcon(path: change.path)
                Text((change.path as NSString).lastPathComponent).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 8)
                AssistantChangeCounts(change: change)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .help(change.path)
    }
}

struct AssistantFileIcon: View {
    let path: String
    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(for: UTType(filenameExtension: (path as NSString).pathExtension) ?? .plainText))
            .resizable().frame(width: 16, height: 16)
    }
}

/// "+2 −1 M".
struct AssistantChangeCounts: View {
    let change: AssistantFileChange
    var body: some View {
        HStack(spacing: 6) {
            if change.added > 0 { Text("+\(change.added)").foregroundStyle(.green) }
            if change.removed > 0 { Text("\u{2212}\(change.removed)").foregroundStyle(.red) }
            Text(change.isNew ? "A" : "M")
                .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                .frame(width: 15, height: 15)
                .background(Color.blue, in: RoundedRectangle(cornerRadius: 3))
                .help(change.isNew ? "Added" : "Modified")
        }
        .font(.system(size: 12, weight: .medium).monospacedDigit())
    }
}

/// The agent's thought as it streams: its last line, in grey italics, with a spinner.
struct AssistantThinkingRow: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left").foregroundStyle(.secondary)
            Text(lastLine).italic().foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            Spacer(minLength: 8)
            ProgressView().controlSize(.small)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Thinking: \(lastLine)")
    }

    private var lastLine: String {
        text.split(whereSeparator: \.isNewline).last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }
}

/// "Working" with a hammer and a spinner, the text under a slow light sweep.
struct AssistantWorkingRow: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "hammer").foregroundStyle(.secondary)
            AssistantShimmer(text: "Working")
            Spacer(minLength: 8)
            ProgressView().controlSize(.small)
        }
        .padding(.horizontal, 4)
    }
}

/// Text at 30% opacity with a full-opacity band sweeping diagonally across it every 1.5 s; plain with Reduce Motion.
struct AssistantShimmer: View {
    let text: String
    @State private var start = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var direction

    var body: some View {
        if reduceMotion {
            Text(text).foregroundStyle(.secondary)
        } else {
            Text(text).foregroundStyle(.primary)
                .mask(LinearGradient(colors: [.black.opacity(0.3), .black, .black.opacity(0.3)], startPoint: from, endPoint: to))
                .onAppear { withAnimation(.linear(duration: 1.5).delay(0.25).repeatForever(autoreverses: false)) { start = false } }
        }
    }

    /// The band is 0.3 wide: the gradient runs from (-0.3, -0.3)–(0, 0) to (1, 1)–(1.3, 1.3), mirrored right to left.
    private var from: UnitPoint { point(start ? -0.3 : 1) }
    private var to: UnitPoint { point(start ? 0 : 1.3) }
    private func point(_ v: CGFloat) -> UnitPoint { UnitPoint(x: direction == .rightToLeft ? 1 - v : v, y: v) }
}

/// One tool call: a grey row with the kind's icon, the title and its state; expands to what it ran or returned.
struct AssistantToolRow: View {
    let kind: String?
    let title: String
    let status: AssistantToolStatus
    var detail: String?
    @State private var expanded = false

    init(kind: String?, title: String, status: AssistantToolStatus, detail: String? = nil) {
        self.kind = kind; self.title = title; self.status = status; self.detail = detail
    }

    /// A finished call from the transcript; its name is the ACP kind for an agent's call.
    init(exchange e: ToolExchange) {
        self.init(kind: e.call.name, title: e.title, status: e.result == nil ? .inProgress : e.isError ? .failed : .completed, detail: e.result)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { if detail?.isEmpty == false, !status.isRunning { expanded.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: AssistantToolStatus.symbol(kind: kind)).frame(width: 16)
                    Text(title).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    switch status {
                    case .pending, .inProgress: AssistantSpinner()
                    case .completed: Image(systemName: "checkmark").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                    }
                }
                .foregroundStyle(status == .failed ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // A running call shows what it does on one line; a finished one only when expanded, in full.
            if status.isRunning, let line = detail?.split(whereSeparator: \.isNewline).first {
                Text(line).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .transition(.opacity)
            } else if expanded, let detail {
                ScrollView {
                    Text(detail).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                .frame(maxHeight: 160)
                .fixedSize(horizontal: false, vertical: true)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(.easeOut(duration: 0.25), value: status)
        .animation(.easeOut(duration: 0.2), value: expanded)
    }
}

/// A small ring with a turning blue arc, like Xcode's tool-call progress.
struct AssistantSpinner: View {
    @State private var turning = false

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 2)
            Circle().trim(from: 0, to: 0.3).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(turning ? 360 : 0))
                .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: turning)
        }
        .frame(width: 13, height: 13)
        .onAppear { turning = true }
        .accessibilityLabel("In progress")
    }
}

/// New transcript items fade in and rise a little (a plain fade with Reduce Motion); removed ones fade out.
/// They animate only inside the model's animated changes, so opening a conversation shows it at once.
struct AssistantEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .offset(y: 8)).combined(with: .scale(scale: 0.98, anchor: .top)), removal: .opacity))
    }
}

extension View {
    func assistantEntrance() -> some View { modifier(AssistantEntrance()) }
}

/// "11s · 1 file edited · feedback" under a finished turn.
struct AssistantTurnFooter: View {
    let duration: TimeInterval?
    let files: Int
    let feedback: Bool?
    let rate: (Bool?) -> Void
    @State private var asking = false

    var body: some View {
        ZStack {
            if files > 0 { Text(files == 1 ? "1 file edited" : "\(files) files edited") }
            HStack {
                if let duration { Text(AssistantTurns.duration(duration)) }
                Spacer()
                Button { asking.toggle() } label: { Image(systemName: feedback == nil ? "exclamationmark.bubble" : feedback! ? "hand.thumbsup.fill" : "hand.thumbsdown.fill") }
                    .buttonStyle(.plain).help("Rate this answer; kept on this Mac only")
                    .popover(isPresented: $asking, arrowEdge: .top) {
                        HStack(spacing: 12) {
                            Button { rate(feedback == true ? nil : true); asking = false } label: { Image(systemName: feedback == true ? "hand.thumbsup.fill" : "hand.thumbsup") }
                                .accessibilityLabel("Good answer")
                            Button { rate(feedback == false ? nil : false); asking = false } label: { Image(systemName: feedback == false ? "hand.thumbsdown.fill" : "hand.thumbsdown") }
                                .accessibilityLabel("Bad answer")
                        }
                        .buttonStyle(.borderless).font(.title3).padding(10)
                    }
            }
        }
        .font(.callout).foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }
}

/// Markdown prose (headings, lists, emphasis, inline code) with fenced code in cards. Project file names become links.
struct AssistantMarkdown: View {
    let text: String
    var files: Set<String> = []
    var open: (String) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(Self.blocks(text).enumerated()), id: \.offset) { _, b in
                if b.code {
                    AssistantCodeCard(code: b.text, language: b.language)
                } else {
                    ForEach(Array(Self.lines(b.text).enumerated()), id: \.offset) { _, l in line(l) }
                }
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "typo-file" else { return .systemAction }
            open(url.path(percentEncoded: false))
            return .handled
        })
    }

    @ViewBuilder private func line(_ l: (kind: LineKind, text: String)) -> some View {
        switch l.kind {
        case .heading(let level):
            inline(l.text).font(level == 1 ? .title3.bold() : .headline).padding(.top, 4)
        case .bullet(let marker):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(marker).foregroundStyle(.secondary)
                inline(l.text)
            }
            .padding(.leading, 6)
        case .paragraph:
            inline(l.text)
        }
    }

    private func inline(_ s: String) -> some View {
        Text((try? AttributedString(markdown: Self.linkingFiles(s, files), options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s))
            .textSelection(.enabled)
            .lineSpacing(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    enum LineKind { case heading(Int), bullet(String), paragraph }

    /// A prose block as headings, list items and paragraphs (lines of a paragraph joined).
    static func lines(_ block: String) -> [(kind: LineKind, text: String)] {
        var out: [(kind: LineKind, text: String)] = []
        var para: [String] = []
        func flush() { if !para.isEmpty { out.append((.paragraph, para.joined(separator: "\n"))); para = [] } }
        for raw in block.components(separatedBy: "\n") {
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { flush(); continue }
            if let hashes = t.firstIndex(where: { $0 != "#" }), t.hasPrefix("#"), t[hashes] == " " {
                flush(); out.append((.heading(t.distance(from: t.startIndex, to: hashes)), String(t[hashes...]).trimmingCharacters(in: .whitespaces)))
            } else if t.hasPrefix("- ") || t.hasPrefix("* ") {
                flush(); out.append((.bullet("•"), String(t.dropFirst(2))))
            } else if let dot = t.firstIndex(of: "."), t[..<dot].allSatisfy(\.isNumber), !t[..<dot].isEmpty, t[t.index(after: dot)...].hasPrefix(" ") {
                flush(); out.append((.bullet(String(t[...dot])), String(t[t.index(dot, offsetBy: 2)...])))
            } else {
                para.append(t)
            }
        }
        flush()
        return out
    }

    /// Wraps each project file path outside code spans in a link the transcript opens.
    static func linkingFiles(_ s: String, _ files: Set<String>) -> String {
        guard !files.isEmpty else { return s }
        var out = "", inCode = false, word = ""
        func flushWord() {
            let core = word.trimmingCharacters(in: CharacterSet(charactersIn: "*_.,:;()!?"))
            if !inCode, !core.isEmpty, files.contains(core), let r = word.range(of: core) {
                word.replaceSubrange(r, with: "[\(core) ↗](typo-file:\(core.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? core))")
            }
            out += word; word = ""
        }
        for ch in s {
            if ch == "`" { flushWord(); inCode.toggle(); out.append(ch) } else if ch == " " || ch == "\n" { flushWord(); out.append(ch) } else { word.append(ch) }
        }
        flushWord()
        return out
    }

    /// Alternating prose and ``` code blocks with the fence's language; an unclosed fence (still streaming) is code to the end.
    static func blocks(_ text: String) -> [(code: Bool, language: String, text: String)] {
        var out: [(code: Bool, language: String, text: String)] = [], lines: [String] = [], code = false, language = ""
        func flush() {
            let t = lines.joined(separator: "\n")
            if !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append((code, language, code ? t : t.trimmingCharacters(in: .newlines))) }
            lines = []
        }
        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") {
                flush()
                code.toggle()
                language = code ? String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces).lowercased() : ""
            } else {
                lines.append(line)
            }
        }
        flush()
        return out
    }
}

/// Fenced code: a white field inside a grey rounded border; Typst is highlighted like the editor.
struct AssistantCodeCard: View {
    let code: String
    let language: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Group {
                if ["typst", "typ", ""].contains(language) {
                    Text(AssistantChangeCard.highlighted(code, path: "snippet.typ"))
                } else {
                    Text(code).font(Font(Highlighter.baseFont))
                }
            }
            .textSelection(.enabled)
            .fixedSize()
            .padding(10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(6)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .contextMenu {
            Button("Copy Code") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
            }
        }
    }
}
