import SwiftUI
import TypoAssistant

/// Settings › Intelligence › Skills: Typo's bundled skills and the user's own, each switched on or off for agents.
struct SkillsSettings: View {
    private let store = SkillStore.shared
    /// The open editor: a new or existing skill of My Skills, or a bundled one to read.
    @State private var editing: SkillDraft?
    @State private var deleting: Skill?
    @State private var error: String?

    var body: some View {
        Form {
            SettingsHeaderCard(symbol: "rosette", fill: AnyShapeStyle(Color.indigo.gradient), title: "Skills",
                               text: "Skills are instructions an agent reads when a task calls for them, such as writing Typst tables or fixing compile errors. Write your own in plain words.")
            Section("Typo Skills") {
                ForEach(store.bundledSkills) { skill in
                    row(skill, plugin: SkillStore.bundled!) {
                        Button("View") { editing = SkillDraft(skill: skill, bundled: true) }
                    }
                    .contextMenu { Button("Duplicate as My Skill") { duplicate(skill) } }
                }
                if store.bundledSkills.isEmpty {
                    Text("This build of Typo has no bundled skills.").foregroundStyle(.secondary)
                }
            }
            Section {
                ForEach(store.userSkills) { skill in
                    row(skill, plugin: SkillStore.user) {
                        Button("Edit") { editing = SkillDraft(skill: skill, bundled: false) }
                        Menu {
                            Button("Duplicate") { duplicate(skill) }
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([SkillStore.user.folder(skill.name).appending(path: "SKILL.md")]) }
                            Divider()
                            Button("Delete…", role: .destructive) { deleting = skill }
                        } label: { Image(systemName: "ellipsis") }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            .accessibilityLabel("More")
                    }
                    .contextMenu {
                        Button("Edit") { editing = SkillDraft(skill: skill, bundled: false) }
                        Button("Duplicate") { duplicate(skill) }
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([SkillStore.user.folder(skill.name).appending(path: "SKILL.md")]) }
                        Button("Delete…", role: .destructive) { deleting = skill }
                    }
                }
                if store.userSkills.isEmpty {
                    VStack(spacing: 4) {
                        Text("No Skills of Your Own").foregroundStyle(.secondary)
                        Text("Write down how you like things done, such as your thesis template's conventions, and agents follow it.")
                            .font(.callout).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
            } header: {
                Text("My Skills")
            } footer: {
                VStack(alignment: .trailing, spacing: 10) {
                    HStack {
                        Spacer()
                        Menu("Duplicate as My Skill") {
                            ForEach(store.bundledSkills) { s in Button(s.name) { duplicate(s) } }
                        }
                        .fixedSize()
                        Button("New Skill") { editing = SkillDraft(skill: Skill(name: "", description: "", body: ""), bundled: false, isNew: true) }
                    }
                    if let error { Text(error).font(.callout).foregroundStyle(.red) }
                    Text("Claude Code loads the skills that are on when a conversation starts; changes apply to new conversations. Other agents don't load skills yet.")
                        .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .pane()
        .onAppear { store.reload() }
        .sheet(item: $editing) { SkillEditorSheet(draft: $0) { editing = SkillDraft(skill: $0, bundled: false, isNew: true) } }
        .confirmationDialog("Delete “\(deleting?.name ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Move to Trash", role: .destructive) {
                if let d = deleting { do { try store.delete(d) } catch { self.error = error.localizedDescription } }
            }
        } message: {
            Text("The skill moves to the Trash.")
        }
    }

    private func row(_ skill: Skill, plugin: SkillPlugin, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "rosette").font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                .frame(width: 28, height: 28).background(Color.indigo.gradient, in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name)
                Text(skill.description.isEmpty ? "No description" : skill.description).font(.callout).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            trailing()
            Toggle("On", isOn: Binding(get: { store.isOn(skill, in: plugin) }, set: { store.set(skill, in: plugin, on: $0) }))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
                .accessibilityLabel("Use \(skill.name)")
        }
    }

    /// Opens a copy of `skill` as a new skill of My Skills, under a free name.
    private func duplicate(_ skill: Skill) {
        var copy = skill
        copy.name = Skill.unique(skill.name + "-copy", among: store.names)
        editing = SkillDraft(skill: copy, bundled: false, isNew: true)
    }
}

/// A skill open in the editor.
struct SkillDraft: Identifiable {
    let id = UUID()
    var skill: Skill
    /// A bundled skill: shown read-only.
    var bundled: Bool
    var isNew = false
}

/// The skill editor: a title that gives the name, when to use it, and the text as Markdown that looks like writing.
struct SkillEditorSheet: View {
    let draft: SkillDraft
    /// "Duplicate as My Skill" from a bundled skill: the caller opens the copy.
    let duplicate: (Skill) -> Void
    @Environment(\.dismiss) private var dismiss
    private let store = SkillStore.shared
    @State private var title = ""
    @State private var name = ""
    /// The user typed a name, so the title no longer sets it.
    @State private var nameEdited = false
    @State private var description = ""
    @State private var text = ""
    @State private var actions: MarkdownActions?
    @State private var confirmDiscard = false
    @State private var error: String?

    private var original: Skill { draft.skill }
    private var current: Skill { Skill(name: name, description: description.trimmingCharacters(in: .whitespacesAndNewlines), body: text) }
    private var changed: Bool { current != original }

    /// Why the name cannot be saved, or nil.
    private var nameProblem: String? {
        if name.isEmpty { return "Enter a title or a name." }
        if !Skill.isValidName(name) { return "Use lowercase letters, digits and single hyphens." }
        if name != original.name || draft.isNew, store.names.contains(name) { return "A skill named “\(name)” exists already." }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if draft.bundled {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "rosette").font(.system(size: 17, weight: .medium)).foregroundStyle(.white)
                        .frame(width: 32, height: 32).background(Color.indigo.gradient, in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name).font(.headline)
                        Text(description).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 25).padding(.top, 20).padding(.bottom, 8)
            } else {
                Form {
                    TextField("Title", text: $title, prompt: Text("Write Tables Like I Do"))
                        .onChange(of: title) { if !nameEdited { name = Skill.slug(title) } }
                    VStack(alignment: .leading, spacing: 3) {
                        LabeledContent("Name") {
                            TextField("Name", text: Binding(get: { name }, set: { name = $0; nameEdited = true }), prompt: Text("write-tables-like-i-do"))
                                .labelsHidden().multilineTextAlignment(.trailing).font(.body.monospaced())
                        }
                        if let nameProblem, !(draft.isNew && name.isEmpty && title.isEmpty) {
                            Text(nameProblem).font(.callout).foregroundStyle(.red)
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        TextField("When to use", text: $description, prompt: Text("Use when the user asks for a table in Typst."))
                        Text("The agent reads this line to decide when the skill applies, so say when, not only what.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)
                .scrollDisabled(true)
                .frame(height: 168)
            }
            if !draft.bundled { formatBar }
            MarkdownTextView(text: $text, editable: !draft.bundled, actions: $actions)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(alignment: .top) { if !draft.bundled { Divider() } }
            Divider()
            HStack {
                if let error { Text(error).font(.callout).foregroundStyle(.red).lineLimit(2) }
                Spacer()
                if draft.bundled {
                    Button("Duplicate as My Skill") { duplicate(duplicated) }   // swaps this sheet for the editor
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
        .frame(width: 640, height: 500)
        .interactiveDismissDisabled(!draft.bundled && changed)
        .onAppear {
            name = original.name
            nameEdited = false   // the title below gives the same name back
            title = original.name.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
            description = original.description
            text = original.body
        }
        .confirmationDialog("Discard your changes to this skill?", isPresented: $confirmDiscard) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        }
    }

    /// A bundled skill as a new skill of My Skills.
    private var duplicated: Skill {
        var s = original
        s.name = Skill.unique(s.name + "-copy", among: store.names)
        return s
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
