import SwiftUI
import TypoAssistant

/// Settings › Intelligence › Workflows: Typo's built-in workflows and the user's own, started with "/" in a conversation.
struct WorkflowsSettings: View {
    private let store = WorkflowStore.shared
    /// The open editor: a new or existing workflow of My Workflows, or a built-in one to read.
    @State private var editing: WorkflowDraft?
    @State private var deleting: Workflow?
    @State private var error: String?

    var body: some View {
        Form {
            SettingsHeaderCard(symbol: "bolt.horizontal.fill", fill: AnyShapeStyle(Color.orange.gradient), title: "Workflows",
                               text: "Type / in a conversation to run one. Typo sends its instructions to whichever model you use. Write your own for the things you do often.")
            Section("Typo") {
                ForEach(store.builtIns) { workflow in
                    row(workflow) {
                        Button("View") { editing = WorkflowDraft(workflow: workflow) }
                        Toggle("On", isOn: Binding(get: { store.isOn(workflow) }, set: { store.set(workflow, on: $0) }))
                            .labelsHidden().toggleStyle(.switch).controlSize(.small)
                            .accessibilityLabel("Use \(workflow.name)")
                    }
                    .contextMenu { Button("Duplicate as My Workflow") { duplicate(workflow) } }
                }
                if store.builtIns.isEmpty {
                    Text("This build of Typo has no built-in workflows.").foregroundStyle(.secondary)
                }
            }
            Section {
                ForEach(store.mine) { workflow in
                    row(workflow) {
                        Button("Edit") { editing = WorkflowDraft(workflow: workflow) }
                        Menu {
                            Button("Duplicate") { duplicate(workflow) }
                            Button("Show in Finder") { reveal(workflow) }
                            Divider()
                            Button("Delete…", role: .destructive) { deleting = workflow }
                        } label: { Image(systemName: "ellipsis") }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            .accessibilityLabel("More")
                    }
                    .contextMenu {
                        Button("Edit") { editing = WorkflowDraft(workflow: workflow) }
                        Button("Duplicate") { duplicate(workflow) }
                        Button("Show in Finder") { reveal(workflow) }
                        Button("Delete…", role: .destructive) { deleting = workflow }
                    }
                }
                if store.mine.isEmpty {
                    VStack(spacing: 4) {
                        Text("No Workflows of Your Own").foregroundStyle(.secondary)
                        Text("Write down a task you repeat, such as checking your thesis against its template, and start it with /.")
                            .font(.callout).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
            } header: {
                Text("My Workflows")
            } footer: {
                VStack(alignment: .trailing, spacing: 10) {
                    HStack {
                        Spacer()
                        Menu("Duplicate…") {
                            ForEach(store.builtIns + store.mine) { w in Button(w.name) { duplicate(w) } }
                        }
                        .fixedSize()
                        Button("New Workflow") { editing = WorkflowDraft(workflow: Workflow(name: "", description: "", body: ""), isNew: true) }
                    }
                    if let error { Text(error).font(.callout).foregroundStyle(.red) }
                }
            }
        }
        .pane()
        .onAppear { store.reload() }
        .sheet(item: $editing) { WorkflowEditorSheet(draft: $0) { editing = WorkflowDraft(workflow: $0, isNew: true) } }
        .confirmationDialog("Delete “\(deleting?.name ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Move to Trash", role: .destructive) {
                if let d = deleting { do { try store.delete(d) } catch { self.error = error.localizedDescription } }
            }
        } message: {
            Text("The workflow moves to the Trash.")
        }
    }

    private func row(_ workflow: Workflow, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.horizontal").font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                .frame(width: 28, height: 28).background(Color.orange.gradient, in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text("/" + workflow.name)
                Text(workflow.description.isEmpty ? String(localized: "No description") : workflow.description).font(.callout).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            trailing()
        }
    }

    private func reveal(_ workflow: Workflow) {
        NSWorkspace.shared.activateFileViewerSelecting([WorkflowStore.user.file(workflow.name)])
    }

    /// Opens a copy of `workflow` as a new workflow of My Workflows, under a free name.
    private func duplicate(_ workflow: Workflow) {
        var copy = workflow
        copy.name = Workflow.unique(workflow.name + "-copy", among: store.names)
        copy.source = .mine
        editing = WorkflowDraft(workflow: copy, isNew: true)
    }
}

/// A workflow open in the editor.
struct WorkflowDraft: Identifiable {
    let id = UUID()
    var workflow: Workflow
    var isNew = false
    /// A built-in workflow: shown read-only.
    var readOnly: Bool { workflow.source == .builtIn }
}

/// The workflow editor: name, description, argument hint, and the instructions as Markdown that looks like writing.
struct WorkflowEditorSheet: View {
    let draft: WorkflowDraft
    /// "Duplicate as My Workflow" from a built-in one: the caller opens the copy.
    let duplicate: (Workflow) -> Void
    @Environment(\.dismiss) private var dismiss
    private let store = WorkflowStore.shared
    @State private var name = ""
    @State private var description = ""
    @State private var argumentHint = ""
    @State private var text = ""
    @State private var actions: MarkdownActions?
    @State private var confirmDiscard = false
    @State private var error: String?

    private var original: Workflow { draft.workflow }
    private var current: Workflow {
        Workflow(name: name, description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                 argumentHint: argumentHint.trimmingCharacters(in: .whitespacesAndNewlines), body: text, source: .mine)
    }
    private var changed: Bool { current != original }

    /// Why the name cannot be saved, or nil.
    private var nameProblem: String? {
        if name.isEmpty { return String(localized: "Enter a name.") }
        if !Workflow.isValidName(name) { return String(localized: "Use lowercase letters, digits and single hyphens.") }
        if name != original.name || draft.isNew, store.names.contains(name) { return String(localized: "A workflow named “\(name)” exists already.") }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if draft.readOnly {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "bolt.horizontal").font(.system(size: 17, weight: .medium)).foregroundStyle(.white)
                        .frame(width: 32, height: 32).background(Color.orange.gradient, in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("/" + name).font(.headline)
                        Text(description).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 25).padding(.top, 20).padding(.bottom, 8)
            } else {
                Form {
                    VStack(alignment: .leading, spacing: 3) {
                        LabeledContent("Name") {
                            TextField("Name", text: $name, prompt: Text("check-my-tables"))
                                .labelsHidden().multilineTextAlignment(.trailing).font(.body.monospaced())
                        }
                        if let nameProblem, !(draft.isNew && name.isEmpty) {
                            Text(nameProblem).font(.callout).foregroundStyle(.red)
                        }
                    }
                    TextField("Description", text: $description, prompt: Text("Make every table in the project match the template."))
                    VStack(alignment: .leading, spacing: 3) {
                        TextField("Argument hint", text: $argumentHint, prompt: Text("[what to type after the name]"))
                        Text("Use $ARGUMENTS where the text typed after the name goes.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
                .frame(height: 190)
            }
            if !draft.readOnly { formatBar }
            MarkdownTextView(text: $text, editable: !draft.readOnly, actions: $actions)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(alignment: .top) { if !draft.readOnly { Divider() } }
            Divider()
            HStack {
                if let error { Text(error).font(.callout).foregroundStyle(.red).lineLimit(2) }
                Spacer()
                if draft.readOnly {
                    Button("Duplicate as My Workflow") { duplicate(duplicated) }   // swaps this sheet for the editor
                    Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel", role: .cancel) { if changed { confirmDiscard = true } else { dismiss() } }
                        .keyboardShortcut(.cancelAction)
                    Button("Save") { save() }
                        .keyboardShortcut("s", modifiers: .command)
                        .buttonStyle(.borderedProminent)
                        .disabled(nameProblem != nil || current.description.isEmpty || !(draft.isNew || changed))
                }
            }
            .controlSize(.large)
            .padding(16)
        }
        .frame(width: 640, height: 520)
        .interactiveDismissDisabled(!draft.readOnly && changed)
        .onAppear {
            name = original.name
            description = original.description
            argumentHint = original.argumentHint
            text = original.body
        }
        .confirmationDialog("Discard your changes to this workflow?", isPresented: $confirmDiscard) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        }
    }

    /// A built-in workflow as a new workflow of My Workflows.
    private var duplicated: Workflow {
        var w = original
        w.name = Workflow.unique(w.name + "-copy", among: store.names)
        w.source = .mine
        return w
    }

    private var formatBar: some View {
        HStack(spacing: 2) {
            Group {
                Button { actions?.wrap("**") } label: { Image(systemName: "bold") }.help("Bold").accessibilityLabel("Bold")
                Button { actions?.wrap("*") } label: { Image(systemName: "italic") }.help("Italic").accessibilityLabel("Italic")
                Button { actions?.wrap("`") } label: { Image(systemName: "chevron.left.forwardslash.chevron.right") }.help("Code").accessibilityLabel("Code")
                Divider().frame(height: 16).padding(.horizontal, 4)
                Button { actions?.prefixLines("## ") } label: { Image(systemName: "textformat.size") }.help("Heading").accessibilityLabel("Heading")
                Button { actions?.prefixLines("- ") } label: { Image(systemName: "list.bullet") }.help("Bulleted List").accessibilityLabel("Bulleted List")
                Button { actions?.prefixLines("1. ") } label: { Image(systemName: "list.number") }.help("Numbered List").accessibilityLabel("Numbered List")
            }
            .buttonStyle(.borderless)
            .frame(minWidth: 26, minHeight: 22)
            Spacer()
            Text("Markdown").font(.callout).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20).padding(.vertical, 6)
    }

    private func save() {
        do {
            try store.save(current, replacing: draft.isNew ? nil : original.name)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
