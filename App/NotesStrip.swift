import AppKit
import SwiftUI
import TypoAssistant
import TypoKit

extension SettingsKey {
    static let notesStripHeight = "notesStripHeight"
}

/// The presenter notes of the slide in view, under the preview. A slide with at most one Typo note is edited here;
/// Touying and Polylux notes are shown and jump to their call in the source.
struct NotesStrip: View {
    let project: Project
    private let providers = AssistantProviderStore.shared
    @Environment(\.openSettings) private var openSettings
    @AppStorage(SettingsKey.notesStripHeight) private var storedHeight = 110.0
    @State private var startHeight: Double?
    @State private var notes: [PresenterNote] = []
    /// Bumped after a write from here, so the strip rereads the notes even when the pages look the same.
    @State private var written = 0
    @State private var adding: Int?
    @State private var drafting = Drafting.idle
    @State private var task: Task<Void, Never>?
    private var preview: PreviewModel { project.preview }

    private static let minHeight = 70.0, maxHeight = 480.0

    private var page: Int { min(max(preview.visiblePage, 0), max(preview.pages.count - 1, 0)) }
    private var slideNotes: [PresenterNote] { notes.filter { $0.pages.contains(page) } }
    private var height: Double { min(max(storedHeight, Self.minHeight), Self.maxHeight) }

    private struct Refresh: Equatable { let hashes: [UInt128]; let revision: Int; let written: Int }

    enum Drafting: Equatable {
        case idle, running, noProvider
        case consent(UUID)
        case failed(String)
        case draft(page: Int, text: String)
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider().overlay { Color.clear.frame(height: 8).contentShape(Rectangle()).pointerStyle(.rowResize).gesture(resize) }
            header
            content
        }
        .frame(height: height)
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: Refresh(hashes: preview.pages.map(\.hash), revision: project.compileRevision, written: written)) {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            let found = await project.presenterNotes()
            if !Task.isCancelled { notes = found }
        }
        .onChange(of: page) { adding = nil }
        .onDisappear { task?.cancel() }
    }

    private var resize: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { v in
                let start = startHeight ?? height
                startHeight = start
                storedHeight = min(max(start - v.translation.height, Self.minHeight), Self.maxHeight)
            }
            .onEnded { _ in startHeight = nil }
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 6) {
            Text("Notes · Slide \(page + 1)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            if drafting == .running { ProgressView().controlSize(.small) }
            Button { startDraft() } label: { Image(systemName: "sparkles") }
                .buttonStyle(.borderless)
                .disabled(drafting == .running || preview.pages.isEmpty)
                .accessibilityLabel("Draft Notes with AI")
                .help("Draft Notes with AI")
        }
        .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 2)
    }

    // MARK: content

    @ViewBuilder private var content: some View {
        switch drafting {
        case .consent(let id):
            if let p = providers.provider(id) { consent(p) }
        case .noProvider:
            status(Label("Set Up a Model Provider", systemImage: "sparkles")) {
                Button("Cancel") { drafting = .idle }
                Button("Open Intelligence Settings") {
                    UserDefaults.standard.set("intelligence", forKey: SettingsKey.tab)
                    openSettings()
                    drafting = .idle
                }
            }
        case .failed(let message):
            status(Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange), actions: { Button("Discard") { drafting = .idle } })
        case .draft(let draftPage, let text) where draftPage == page:
            draft(text)
        default:
            slide
        }
    }

    @ViewBuilder private var slide: some View {
        let here = slideNotes
        let typo = here.filter { $0.kind == .typo }
        if here.isEmpty && adding != page {
            HStack(spacing: 10) {
                Text("No notes for this slide").foregroundStyle(.secondary)
                Button("Add Note") { adding = page }.controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if typo.count == here.count && typo.count <= 1 {
            let note = typo.first
            NoteEditor(initial: note?.text ?? "", focusOnAppear: note == nil, onCommit: { commit($0, replacing: note, onPage: page) }) {
                if let note { project.reveal(note) }
            }
            .id(NoteIdentity(page: page, text: note?.text, range: note?.callRange))
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(here.enumerated()), id: \.offset) { i, note in
                        if i > 0 { Divider().padding(.vertical, 6) }
                        Button { project.reveal(note) } label: {
                            Text(note.text.isEmpty ? " " : note.text).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Show in Source")
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
            }
        }
    }

    private struct NoteIdentity: Hashable { let page: Int; let text: String?; let range: NSRange? }

    private func commit(_ text: String, replacing note: PresenterNote?, onPage page: Int) {
        adding = nil
        Task {
            await project.setPresenterNote(text, replacing: note, onPage: page, actionName: String(localized: "Edit Presenter Note"))
            written += 1
        }
    }

    // MARK: AI draft

    private func draft(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView { Text(text).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
            HStack {
                Spacer()
                Button("Discard") { drafting = .idle }
                Button("Use") {
                    // The one Typo note of the slide is replaced; with none (or several) the draft becomes a new note.
                    let typo = slideNotes.filter { $0.kind == .typo }
                    let page = page
                    drafting = .idle
                    commit(text, replacing: typo.count == 1 ? typo.first : nil, onPage: page)
                }
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 10).padding(.bottom, 8)
    }

    private func status(_ label: some View, @ViewBuilder actions: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            label.font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer()
            actions().controlSize(.small)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    /// The same notice the chat shows before a provider first receives anything.
    private func consent(_ p: AssistantProvider) -> some View {
        status(Label("The source of this slide and its neighbours will be sent to \(p.name) (\(p.host)).", systemImage: "network")) {
            Button("Cancel") { drafting = .idle }
            Button("Allow") {
                providers.consent(p)
                startDraft()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private func startDraft() {
        providers.refreshAvailability()
        guard let p = providers.defaultModelProvider, providers.isReady(p) else {
            drafting = .noProvider
            return
        }
        if providers.needsConsent(p) { drafting = .consent(p.id); return }
        let page = page, client = providers.client(for: p), model = providers.defaultModel(for: p)
        drafting = .running
        task?.cancel()
        task = Task {
            do {
                let text = try await project.draftPresenterNote(page: page, using: Self.drafter(client, model: model))
                try Task.checkCancellation()
                drafting = text.map { .draft(page: page, text: $0) } ?? .failed(String(localized: "This slide has no text to write notes for."))
            } catch is CancellationError {
                drafting = .idle
            } catch let e as AssistantError {
                drafting = .failed(e.message)
            } catch {
                drafting = Task.isCancelled ? .idle : .failed(error.localizedDescription)
            }
        }
    }

    /// One request, answered in full: the text events of the stream joined.
    static func drafter(_ client: any AssistantClient, model: String) -> PresenterNoteDrafter {
        { system, message in
            var reply = ""
            let request = AssistantRequest(model: model, system: system, files: nil, messages: [.init(role: .user, text: message)])
            for try await e in client.stream(request) {
                if case .text(let t) = e { reply += t }
            }
            return reply
        }
    }
}

/// A multi-line field for one note: it writes back when it loses focus, on ⌘↩ and when it goes away.
private struct NoteEditor: View {
    let initial: String
    let focusOnAppear: Bool
    let onCommit: (String) -> Void
    let reveal: () -> Void
    @State private var text: String
    @State private var committed: String?
    @FocusState private var focused: Bool

    init(initial: String, focusOnAppear: Bool, onCommit: @escaping (String) -> Void, reveal: @escaping () -> Void) {
        self.initial = initial; self.focusOnAppear = focusOnAppear; self.onCommit = onCommit; self.reveal = reveal
        _text = State(initialValue: initial)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .focused($focused)
                .accessibilityLabel("Notes")
            Button { reveal() } label: { Image(systemName: "arrow.right.circle") }
                .buttonStyle(.borderless)
                .opacity(initial.isEmpty ? 0 : 1)
                .accessibilityLabel("Show in Source")
                .help("Show in Source")
                .padding(.top, 6)
            Button("") { focused = false }
                .keyboardShortcut(.return, modifiers: .command)
                .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
        }
        .padding(.horizontal, 6)
        .onAppear { if focusOnAppear { focused = true } }
        .onChange(of: focused) { _, now in if !now { commitIfChanged() } }
        .onDisappear { commitIfChanged() }
    }

    private func commitIfChanged() {
        let new = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard new != initial, new != committed else { return }
        committed = new
        onCommit(new)
    }
}
