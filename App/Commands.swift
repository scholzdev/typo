import AppKit
import SwiftUI
import TypoKit
import UniformTypeIdentifiers
import TypstEngine

struct ProjectCommands: Commands {
    let recents: RecentProjects
    private let focus = FocusedCommandContext()

    private var context: AppCommandContext { focus.context(recents: recents) }

    var body: some Commands {
        let ctx = context
        CommandGroup(replacing: .newItem) {    // instead of an empty project window
            AppCommands.items(AppCommands.newProject(ctx))
        }
        CommandGroup(after: .newItem) {
            AppCommands.items(AppCommands.open(ctx))
            Menu {
                ForEach(recents.records, id: \.id) { r in
                    Button(r.name) { ctx.openWindow(value: r.id) }
                }
            } label: { Label("Open Recent", systemImage: "clock") }
            .disabled(recents.records.isEmpty)
            Divider()
            AppCommands.items(AppCommands.fileItems(ctx))
        }
        CommandGroup(after: .newItem) {    // .saveItem items never appear in this app (no document scene)
            Divider()
            AppCommands.items(AppCommands.save(ctx))
        }
        CommandMenu("Format") {
            AppCommands.items(AppCommands.format(ctx))
        }
        CommandGroup(after: .toolbar) {
            AppCommands.items(AppCommands.preview(ctx))
            NoteDisplayMenu()
        }
    }
}

extension Project {
    /// The previewed document's name with a .pdf extension.
    var pdfFileName: String { (main.raw as NSString).deletingPathExtension.components(separatedBy: "/").last! + ".pdf" }
}

@MainActor func showExportFailure(_ error: any Error, pdfUA: Bool = false) {
    // Typst's PDF/UA errors mostly name no place; the pre-flight hints do.
    let pointer = "\n\n" + String(localized: "PDF/UA problems are listed with their places in the Issue navigator when the export target is PDF/UA-1 or Accessibility checks is set to Always.")
    if case ProjectError.compileFailed(let diagnostics) = error {
        showAlert("The Document Has Errors", verbatim: diagnostics.first?.message ?? String(localized: "It could not be compiled."))
    } else if pdfUA, case ProjectError.exportFailed(let message) = error {
        showAlert("Could Not Export", verbatim: message + pointer)
    } else {
        showAlert("Could Not Export", error)
    }
}

/// View › Presenter Notes in Editor: cards, compact or hidden, as a submenu with a check mark.
private struct NoteDisplayMenu: View {
    @AppStorage(NoteDisplay.key) private var display = NoteDisplay.cards.rawValue

    var body: some View {
        Picker("Presenter Notes in Editor", selection: Binding(get: { display }, set: {
            display = $0
            NotificationCenter.default.post(name: NoteDisplay.changed, object: nil)
        })) {
            Text("Cards").tag(NoteDisplay.cards.rawValue)
            Text("Compact").tag(NoteDisplay.compact.rawValue)
            Text("Hidden").tag(NoteDisplay.hidden.rawValue)
        }
    }
}
