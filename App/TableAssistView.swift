import AppKit
import SwiftUI
import TypoKit
import TypoAssistant

/// The table editor's Intelligence popover: a request (typed or a suggestion) goes to a model with the table,
/// and the table it answers with replaces the cells as one undoable step.
struct TableAssistPopover: View {
    let state: TableSheetState
    private let providers = AssistantProviderStore.shared
    @Environment(\.openSettings) private var openSettings
    @State private var prompt = ""
    @State private var providerID: UUID?
    @State private var modelName = ""
    @State private var phase = Phase.idle
    @State private var task: Task<Void, Never>?
    @State private var lastRequest = ""
    /// A send held until the user accepts that the table goes to this provider.
    @State private var consenting: AssistantProvider?
    @FocusState private var focused: Bool

    enum Phase: Equatable {
        case idle, running
        case failed(String)
        /// `applied` is nil when the answer left the table as it was.
        case done(summary: String?, applied: TableModel?)
    }

    private var provider: AssistantProvider? {
        if let p = providers.provider(providerID), providers.isReady(p) { return p }
        return providers.defaultModelProvider
    }

    private var model: String {
        guard let p = provider else { return "" }
        return p.id == providerID && !modelName.isEmpty ? modelName : providers.defaultModel(for: p)
    }

    var body: some View {
        Group {
            if !providers.hasReadyProvider {
                ContentUnavailableView {
                    Label("Set Up a Model Provider", systemImage: "sparkles")
                } description: {
                    Text(providers.onDevice.isAvailable ? "" : "\(providers.onDevice.status). You can also add a model provider with your own API key.")
                } actions: {
                    Button("Open Intelligence Settings") {
                        UserDefaults.standard.set("intelligence", forKey: SettingsKey.tab)
                        openSettings()
                    }
                }
            } else if let p = consenting {
                consent(p)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    promptBox
                    suggestions
                    status
                }
            }
        }
        .padding(14)
        .frame(width: 380)
        .onAppear { providers.refreshAvailability(); focused = true }
        .onDisappear { task?.cancel() }
    }

    // MARK: prompt

    private var promptBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Describe a change…", text: $prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...6)
                .focused($focused)
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.shift) {
                        NSApp.sendAction(#selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)), to: nil, from: nil)
                    } else {
                        run(prompt)
                    }
                    return .handled
                }
            HStack(spacing: 8) {
                providerMenu
                Spacer()
                if phase == .running {
                    Button { stop() } label: { Image(systemName: "stop.circle.fill").font(.title2) }
                        .buttonStyle(.plain).accessibilityLabel("Stop").help("Stop")
                } else {
                    Button { run(prompt) } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                        .buttonStyle(.plain).accessibilityLabel("Send").help("Send (Return)")
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || provider == nil)
                }
            }
        }
        .padding(10)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
        .overlay { if phase == .running { AssistantGlow() } }
    }

    private var providerMenu: some View {
        Menu {
            ForEach(providers.providers.filter { !$0.isAgent }) { p in
                let models = Array(Set([providers.defaultModel(for: p), p.model] + p.preset.models).filter { !$0.isEmpty }).sorted()
                if p.isOnDevice || models.count <= 1 {
                    Button(p.isOnDevice ? p.name : "\(p.name) – \(models.first ?? p.model)") { choose(p, models.first ?? p.model) }
                        .disabled(!providers.isReady(p))
                } else {
                    Menu(p.name) { ForEach(models, id: \.self) { m in Button(m) { choose(p, m) } } }
                        .disabled(!providers.isReady(p))
                }
            }
        } label: {
            Text(provider.map { $0.isOnDevice ? $0.name : "\($0.name) · \(model)" } ?? "Choose a Model").font(.caption)
        }
        .menuStyle(.borderlessButton).fixedSize()
        .disabled(phase == .running)
        .accessibilityLabel("Model").help("The model provider and model the table goes to")
    }

    private func choose(_ p: AssistantProvider, _ m: String) {
        providerID = p.id
        modelName = m
    }

    // MARK: suggestions

    private var suggestions: some View {
        let column = TableGridView.columnName(state.selectedColumns.lowerBound)
        let chips: [(title: String, request: String?)] = [
            ("Sort by \(column)", "Sort the body rows by column \(column), ascending. The header row stays first."),
            ("Add totals row", "Add a totals row at the bottom that sums the numeric columns."),
            ("Transpose", "Transpose the table: its rows become columns and its columns become rows."),
            ("Fill empty cells", "Fill the empty cells with values that fit their row and column."),
            ("Translate…", nil),
            ("Fix capitalization", "Fix the capitalization of the cell texts consistently: title case in the header, sentence case elsewhere."),
            ("Generate sample data", "Fill the table with realistic sample data that fits its header and caption, keeping its size."),
            ("Format numbers", "Format the numbers consistently: the same decimal places within a column, thousands separators where useful."),
        ]
        return ChipFlow(spacing: 6) {
            ForEach(chips, id: \.title) { chip in
                Button(chip.title) {
                    if let request = chip.request { run(request) } else { prompt = "Translate the cell texts into "; focused = true }
                }
                .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small)
                .disabled(phase == .running)
            }
        }
    }

    // MARK: status

    @ViewBuilder private var status: some View {
        switch phase {
        case .idle:
            EmptyView()
        case .running:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Changing the table…").foregroundStyle(.secondary)
                Spacer()
                Button("Stop", action: stop)
            }
        case .failed(let message):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Retry") { run(lastRequest) }
            }
        case .done(let summary, let applied):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(summary ?? (applied == nil ? "The table is unchanged." : "Changed the table."), systemImage: "sparkles")
                    .symbolRenderingMode(.multicolor)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if let applied, state.model == applied {
                    Button("Undo") { state.undo.undo() }
                }
            }
        }
    }

    /// The same notice the chat shows before a provider first receives anything.
    private func consent(_ p: AssistantProvider) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Send to \(p.name)?", systemImage: "network").font(.headline)
            Text("The table, its caption and your request will be sent to \(p.name) (\(p.host)).")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { consenting = nil }
                Button("Allow") {
                    providers.consent(p)
                    consenting = nil
                    run(lastRequest)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: running

    /// The selection in the grid's names, so "B2:C3" in a request means what the user sees.
    private var selectionName: String {
        let s = state.selection, hr = state.model.headerRows
        func name(_ r: Int, _ c: Int) -> String { TableGridView.columnName(c) + TableGridView.rowName(r, headerRows: hr) }
        let first = name(s.rows.lowerBound, s.columns.lowerBound), last = name(s.rows.upperBound, s.columns.upperBound)
        return (first == last ? first : "\(first):\(last)")
            + " (columns are lettered from A; " + (hr > 0 ? "row H is the header row, " : "") + "body rows are numbered from 1)"
    }

    private func run(_ text: String) {
        let request = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, phase != .running, let p = provider else { return }
        lastRequest = request
        // Nothing leaves the Mac before the provider's notice was accepted.
        if providers.needsConsent(p) { consenting = p; return }
        let before = state.model
        let message = TableAssist.message(markup: TableCode.render(before), caption: before.figure?.caption ?? "", selection: selectionName, request: request)
        let client = providers.client(for: p)
        let assistantRequest = AssistantRequest(model: model, system: TableAssist.system(callee: before.callee), files: nil, messages: [.init(role: .user, text: message)])
        phase = .running
        task = Task {
            do {
                var reply = ""
                for try await e in client.stream(assistantRequest) {
                    if case .text(let t) = e { reply += t }
                }
                try Task.checkCancellation()
                guard state.model == before else { phase = .failed("The table changed while the model was answering."); return }
                guard let result = TableAssist.apply(reply, to: before) else { phase = .failed("Couldn't read the model's table."); return }
                state.change("Intelligence") { $0 = result.model }
                if text == prompt { prompt = "" }
                phase = .done(summary: result.summary, applied: result.model == before ? nil : result.model)
            } catch is CancellationError {
                phase = .idle
            } catch let e as AssistantError {
                phase = .failed(e.message)
            } catch {
                phase = Task.isCancelled ? .idle : .failed(error.localizedDescription)
            }
        }
    }

    private func stop() {
        task?.cancel()
        task = nil
        phase = .idle
    }
}

#Preview("Table Intelligence") {
    let source = """
    #figure(
      table(
        columns: (1fr, auto),
        table.header([*Fruit*], [Price]),
        [Pear], [\\$2.00],
        [Apple], [\\$1.20],
      ),
      caption: [Fruit prices],
    )
    """
    if case .table(let model)? = TableModel.lookup(in: source, at: (source as NSString).range(of: "Apple").location) {
        TableAssistPopover(state: TableSheetState(model: model))
    } else {
        Text("The sample table did not parse")
    }
}

/// Chips in rows, each at its own width, wrapping like text.
private struct ChipFlow: Layout {
    var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }
    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(items: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] {
        var rows: [(items: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] = []
        var current: (items: [Int], y: CGFloat, width: CGFloat, height: CGFloat) = ([], 0, 0, 0)
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            let needed = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.items.isEmpty {
                rows.append(current)
                current = ([], current.y + current.height + spacing, 0, 0)
            }
            current.width = current.items.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.items.append(i)
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}
