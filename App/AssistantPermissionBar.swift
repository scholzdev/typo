import SwiftUI
import TypoKit
import ACPProtocol
import TypoACP

/// Replaces the prompt box while the agent waits for a permission: the question, Don't Allow, the Allow split button
/// with Allow Once, Always Allow… and Permissions Settings…, and Stop. Only the options the agent offered are shown.
struct AssistantPermissionBar: View {
    let model: AssistantModel
    let pending: AssistantModel.PendingPermission
    @Environment(\.openSettings) private var openSettings
    @State private var confirmsAlways = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let plan {
                Label("Ready to code?", systemImage: "checklist").font(.headline)
                ScrollView {
                    AssistantMarkdown(text: plan).padding(10)
                }
                .frame(maxHeight: 240)
                .fixedSize(horizontal: false, vertical: true)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Text(question).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                if let reject = option("reject_once") ?? option("reject_always") {
                    Button { model.answerPermission(reject.id) } label: {
                        Text(plan == nil ? "Don't Allow" : "Keep Planning").frame(maxWidth: .infinity).padding(.vertical, 6)
                            .background(.quaternary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                }
                if plan == nil { allowButton } else { approveButton }
                Button { model.stop() } label: {
                    Image(systemName: "stop.fill").font(.system(size: 10, weight: .bold)).frame(width: 28, height: 28)
                        .background(.quaternary, in: Circle())
                }
                .buttonStyle(.plain).accessibilityLabel("Stop").help("Stop the answer")
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
        .alert("Always allow access?", isPresented: $confirmsAlways) {
            Button("Always Allow") { if let o = option("allow_always") { model.answerPermission(o.id) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.isFileRequest(pending.call) ? model.alwaysAllowNote(pending) ?? "" : [model.alwaysAllowNote(pending), "\(agent) won't ask again before doing this in this session."].compactMap { $0 }.joined(separator: "\n\n"))
        }
    }

    private var agent: String { (model.provider?.name ?? "The agent").replacingOccurrences(of: " (ACP)", with: "") }

    private func option(_ kind: String) -> ACPOption? { pending.options.first { $0.kind == kind } }

    /// File access names the file, project files by their project path; anything else names the tool call.
    private var question: AttributedString {
        let paths = pending.call.paths.map { ACPFiles.projectPath($0, root: model.project.rootURL)?.raw ?? $0 }
        let access = pending.call.kind == "read" ? "Read" : "Read and Write"
        let text = (pending.call.changesFiles || pending.call.kind == "read") && !paths.isEmpty
            ? "Do you want to allow \(agent) **\(access)** access to **\(paths.joined(separator: ", "))**?"
            : "Do you want to allow \(agent) to **\(pending.call.title.isEmpty ? "continue" : pending.call.title)**?"
        return (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }

    /// Claude Code's ExitPlanMode request: the plan to approve, which it adds to the tool's input.
    private var plan: String? {
        guard pending.call.kind == "switch_mode", let p = pending.call.rawInput?["plan"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty else { return nil }
        return p
    }

    @ViewBuilder private var allowButton: some View {
        let once = option("allow_once") ?? option("allow_always")
        splitButton("Allow", disabled: once == nil, action: { if let once { once.kind == "allow_always" ? (confirmsAlways = true) : model.answerPermission(once.id) } }) {
            if let o = option("allow_once") { Button("Allow Once") { model.answerPermission(o.id) } }
            if option("allow_always") != nil { Button(model.isFileRequest(pending.call) ? "Always Allow for This Folder…" : "Always Allow…") { confirmsAlways = true } }
            Divider()
            Button("Permissions Settings…") {
                UserDefaults.standard.set("intelligence", forKey: SettingsKey.tab)
                openSettings()
            }
        }
    }

    /// Approve goes on with the edits still asked about; the menu has the agent's other ways to go on, by its names.
    /// Not through the Always Allow alert: they change the agent's mode, not Settings › Permissions.
    @ViewBuilder private var approveButton: some View {
        let allows = pending.options.filter { $0.kind.hasPrefix("allow") }
        let main = option("allow_once") ?? allows.first
        splitButton("Approve", disabled: main == nil, action: { if let main { model.answerPermission(main.id) } }) {
            ForEach(allows) { o in Button(o.name) { model.answerPermission(o.id) } }
        }
    }

    private func splitButton<M: View>(_ title: String, disabled: Bool, action: @escaping () -> Void, @ViewBuilder menu: () -> M) -> some View {
        HStack(spacing: 0) {
            Button(action: action) {
                Text(title).frame(maxWidth: .infinity).padding(.vertical, 6).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .disabled(disabled)
            Divider().frame(height: 16).overlay(.white.opacity(0.5))
            Menu {
                menu()
            } label: {
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .padding(.horizontal, 10)
            .accessibilityLabel("More Options")
        }
        .foregroundStyle(.white)
        .tint(.white)
        .background(Color.accentColor, in: Capsule())
    }
}
