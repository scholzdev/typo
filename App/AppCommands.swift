import AppKit
import SwiftUI
import TypoKit
import TypstEngine

/// One menu command; the menus and the command palette (⇧⌘P) both render from these.
struct AppCommand: Identifiable {
    /// Display values: translated by the String Catalog.
    let menu: LocalizedStringResource
    let title: LocalizedStringResource
    /// Stable and never translated: "Menu/Title" in English. Keys the help texts, stored shortcut overrides and palette recents.
    let id: String
    /// The menu's English name, for grouping and comparisons.
    let menuKey: String
    let systemImage: String
    var shortcut: KeyboardShortcut? = nil
    var isEnabled = true
    /// Non-nil for toggles: the menu shows a Toggle, the palette a checkmark.
    var isOn: Bool? = nil
    /// One short sentence on what the command does, shown in the palette's detail pane.
    var help: LocalizedStringResource? = nil
    let action: @MainActor () -> Void

    /// `idTitle` replaces the title's catalog key in the id when the title interpolates a value.
    init(menu: LocalizedStringResource, title: LocalizedStringResource, idTitle: String? = nil, systemImage: String, shortcut: KeyboardShortcut? = nil,
         isEnabled: Bool = true, isOn: Bool? = nil, help: LocalizedStringResource? = nil, action: @escaping @MainActor () -> Void) {
        self.menu = menu; self.title = title; self.menuKey = menu.key; self.id = "\(menu.key)/\(idTitle ?? title.key)"
        self.systemImage = systemImage; self.shortcut = shortcut; self.isEnabled = isEnabled; self.isOn = isOn; self.help = help; self.action = action
    }

    var entry: PaletteEntry { PaletteEntry(id: id, title: String(localized: title), menu: String(localized: menu), isEnabled: isEnabled) }
}

/// What commands act on: the focused window's objects (FocusedValues), passed in by each Commands struct or the palette.
@MainActor struct AppCommandContext {
    var project: Project?
    var tables: TableEditing?
    var editor: EditorActions?
    var files: FilesController?
    var fileListFocused: Bool?
    var layout: EditorLayout?
    var recents: RecentProjects
    var openWindow: OpenWindowAction
    var sidebar: SidebarModel?
    /// Set by the Shortcuts settings: enumerate every command with no project open (see `GitCommands`).
    var isCatalog = false
    var assistant: AssistantModel? = nil

    var opener: ProjectOpener { ProjectOpener(recents: recents, openWindow: openWindow) }
    /// The pane with keyboard focus: the second while its editor has it.
    var secondPaneFocused: Bool { layout != nil && project?.focusedEditorFile != nil }
}

/// The focused scene's state for a `Commands` struct, which cannot share one set of `@FocusedValue`s.
/// It also observes the shortcut store, so every menu built from it rebuilds when a shortcut changes.
@MainActor struct FocusedCommandContext: DynamicProperty {
    @ObservedObject private var shortcuts = ShortcutStore.shared
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.project) private var project
    @FocusedValue(\.tables) private var tables
    @FocusedValue(\.editorActions) private var editor
    @FocusedValue(\.files) private var files
    @FocusedValue(\.fileListFocused) private var fileListFocused
    @FocusedValue(\.editorLayout) private var layout
    @FocusedValue(\.sidebar) private var sidebar
    @FocusedValue(\.assistant) private var assistant

    @MainActor func context(recents: RecentProjects) -> AppCommandContext {
        AppCommandContext(project: project, tables: tables, editor: editor, files: files, fileListFocused: fileListFocused, layout: layout, recents: recents, openWindow: openWindow, sidebar: sidebar, assistant: assistant)
    }
}

/// The app's menu commands as data, one function per menu section (each inner array sits between Dividers).
@MainActor enum AppCommands {
    static func newProject(_ ctx: AppCommandContext) -> [[AppCommand]] {
        [[AppCommand(menu: "File", title: "New Project…", systemImage: "plus.rectangle.on.folder", shortcut: KeyboardShortcut("n")) { ctx.opener.newProject() },
          AppCommand(menu: "File", title: "New Project from Template…", systemImage: "square.grid.2x2") { ctx.openWindow(id: "templates") }]]
    }

    static func open(_ ctx: AppCommandContext) -> [[AppCommand]] {
        [[AppCommand(menu: "File", title: "Open…", systemImage: "folder", shortcut: KeyboardShortcut("o")) { ctx.opener.choose() }]]
    }

    static func fileItems(_ ctx: AppCommandContext) -> [[AppCommand]] {
        let files = ctx.files
        return [
            [AppCommand(menu: "File", title: "New File…", systemImage: "doc.badge.plus", shortcut: KeyboardShortcut("n", modifiers: [.command, .option]), isEnabled: files != nil) { files?.newFile() },
             AppCommand(menu: "File", title: "New Folder…", systemImage: "folder.badge.plus", shortcut: KeyboardShortcut("n", modifiers: [.command, .shift]), isEnabled: files != nil) { files?.newFolder() }],
            [AppCommand(menu: "File", title: "Rename", systemImage: "pencil", isEnabled: files?.selection != nil) { files?.beginRename() },
             AppCommand(menu: "File", title: "Duplicate", systemImage: "plus.square.on.square", isEnabled: files?.selection != nil) { files?.duplicate() },
             // Enabled only with the file list focused; otherwise the key reaches the editor (delete to line start).
             AppCommand(menu: "File", title: "Move to Trash", systemImage: "trash", shortcut: KeyboardShortcut(.delete, modifiers: .command),
                        isEnabled: !(files?.selection == nil || ctx.fileListFocused != true)) { files?.moveToTrash() }],
            [AppCommand(menu: "File", title: "Connect Zotero…", systemImage: "books.vertical", isEnabled: ctx.layout != nil) { ctx.layout?.connectingZotero = true }],
        ]
    }

    static func save(_ ctx: AppCommandContext) -> [[AppCommand]] {
        let project = ctx.project
        return [[AppCommand(menu: "File", title: "Save", systemImage: "square.and.arrow.down", shortcut: KeyboardShortcut("s"), isEnabled: project != nil) {
            if let project {
                let d = UserDefaults.standard
                let format = d.bool(forKey: SettingsKey.formatOnSave)
                    ? (width: d.object(forKey: SettingsKey.formatWidth) as? Int ?? 80, indent: d.object(forKey: SettingsKey.formatIndent) as? Int ?? 2) : nil
                project.prepareDirtyBuffersForSave(format: format, trimBlankLines: FilePreferences.trimBlankLines())
                Task { try? await project.saveAll() }
            }
        }]]
    }

    static func tabs(_ ctx: AppCommandContext) -> [[AppCommand]] {
        [[AppCommand(menu: "File", title: "New Tab…", systemImage: "plus.rectangle", shortcut: KeyboardShortcut("t"), isEnabled: ctx.layout != nil) { ctx.layout?.quickOpen = .files },
          AppCommand(menu: "File", title: "Close Tab", systemImage: "xmark", shortcut: KeyboardShortcut("w")) { closeTab(ctx) },
          AppCommand(menu: "File", title: "Close Window", systemImage: "xmark.rectangle", shortcut: KeyboardShortcut("w", modifiers: [.command, .shift])) { NSApp.keyWindow?.performClose(nil) }]]
    }

    static func tabSwitching(_ ctx: AppCommandContext) -> [[AppCommand]] {
        [[AppCommand(menu: "Window", title: "Show Next Tab", systemImage: "chevron.right", shortcut: KeyboardShortcut("]", modifiers: [.command, .shift]), isEnabled: ctx.project != nil) { moveTab(ctx, 1) },
          AppCommand(menu: "Window", title: "Show Previous Tab", systemImage: "chevron.left", shortcut: KeyboardShortcut("[", modifiers: [.command, .shift]), isEnabled: ctx.project != nil) { moveTab(ctx, -1) }]]
    }

    static func print(_ ctx: AppCommandContext) -> [[AppCommand]] {
        let project = ctx.project
        return [[AppCommand(menu: "File", title: "Print…", systemImage: "printer", shortcut: KeyboardShortcut("p"), isEnabled: project != nil) { if let project { Task { await ProjectExporter.print(project) } } }]]
    }

    static func export(_ ctx: AppCommandContext) -> [[AppCommand]] {
        let project = ctx.project
        func item(_ title: LocalizedStringResource, _ symbol: String, _ shortcut: KeyboardShortcut? = nil, _ run: @escaping @MainActor (Project) async -> Void) -> AppCommand {
            AppCommand(menu: "Export", title: title, systemImage: symbol, shortcut: shortcut, isEnabled: project != nil) { if let project { Task { await run(project) } } }
        }
        return [[item("PDF…", "doc.richtext", KeyboardShortcut("e", modifiers: [.command, .shift])) { await ExportTarget.pdf.run($0) },
                 item("PDF/A-2b for Archiving…", "archivebox") { await ExportTarget.pdfA2b.run($0) },
                 item("PDF/A-3b for Archiving…", "archivebox") { await ExportTarget.pdfA3b.run($0) },
                 item("PDF/UA-1 (Accessible)…", "accessibility") { await ExportTarget.pdfUA1.run($0) },
                 item("PNG Images…", "photo") { await ExportTarget.png.run($0) },
                 item("SVG Images…", "point.topleft.down.to.point.bottomright.curvepath") { await ExportTarget.svg.run($0) },
                 item("Project Archive (ZIP)…", "doc.zipper") { await ExportTarget.archive.run($0) }]]
    }

    static func snapshots(_ ctx: AppCommandContext) -> [[AppCommand]] {
        let project = ctx.project
        return [[AppCommand(menu: "File", title: "Snapshots\u{2026}", systemImage: "clock.arrow.circlepath", isEnabled: project != nil) { if let project { presentSnapshots(project) } }]]
    }

    /// Edit menu commands that act on the focused editor's text view.
    static func multiCursor() -> [[AppCommand]] {
        func send(_ action: Selector) { NSApp.sendAction(action, to: nil, from: nil) }
        return [[AppCommand(menu: "Edit", title: "Select Next Occurrence", systemImage: "text.magnifyingglass", shortcut: KeyboardShortcut("d")) { send(#selector(EditorTextView.selectNextOccurrence(_:))) },
                 AppCommand(menu: "Edit", title: "Select All Occurrences", systemImage: "text.badge.checkmark", shortcut: KeyboardShortcut("g", modifiers: [.control, .command])) { send(#selector(EditorTextView.selectAllOccurrences(_:))) },
                 AppCommand(menu: "Edit", title: "Add Caret Above", systemImage: "arrow.up.to.line", shortcut: KeyboardShortcut(.upArrow, modifiers: [.control, .shift])) { send(#selector(EditorTextView.addCaretAbove(_:))) },
                 AppCommand(menu: "Edit", title: "Add Caret Below", systemImage: "arrow.down.to.line", shortcut: KeyboardShortcut(.downArrow, modifiers: [.control, .shift])) { send(#selector(EditorTextView.addCaretBelow(_:))) }]]
    }

    static func format(_ ctx: AppCommandContext) -> [[AppCommand]] {
        let editor = ctx.editor, tables = ctx.tables, project = ctx.project
        return [
            // The only owner of these shortcuts: the app adds no TextFormattingCommands (Font menu).
            [AppCommand(menu: "Format", title: "Bold", systemImage: "bold", shortcut: KeyboardShortcut("b"), isEnabled: editor != nil) { editor?.format(.bold) },
             AppCommand(menu: "Format", title: "Italic", systemImage: "italic", shortcut: KeyboardShortcut("i"), isEnabled: editor != nil) { editor?.format(.italic) },
             AppCommand(menu: "Format", title: "Underline", systemImage: "underline", shortcut: KeyboardShortcut("u"), isEnabled: editor != nil) { editor?.format(.underline) }],
            [AppCommand(menu: "Format", title: "Bullet List", systemImage: "list.bullet", isEnabled: editor != nil) { editor?.format(.bulletList) },
             AppCommand(menu: "Format", title: "Numbered List", systemImage: "list.number", isEnabled: editor != nil) { editor?.format(.numberedList) },
             AppCommand(menu: "Format", title: "Math", systemImage: "function", isEnabled: editor != nil) { editor?.format(.math) },
             AppCommand(menu: "Format", title: "Insert Citation…", systemImage: "quote.opening", shortcut: KeyboardShortcut("c", modifiers: [.command, .shift]), isEnabled: editor?.editor != nil) { editor?.citationPickerPresented = true }],
            [AppCommand(menu: "Format", title: "Format Document", systemImage: "text.alignleft", shortcut: KeyboardShortcut("i", modifiers: [.control, .shift]), isEnabled: editor != nil) { editor?.formatCode(selectionOnly: false) },
             AppCommand(menu: "Format", title: "Format Selection", systemImage: "text.line.first.and.arrowtriangle.forward", isEnabled: editor != nil) { editor?.formatCode(selectionOnly: true) },
             AppCommand(menu: "Format", title: "Re-Indent", systemImage: "increase.indent", shortcut: KeyboardShortcut("i", modifiers: [.control]), isEnabled: editor?.editor != nil,
                        help: "Indents the selected lines, or the current line, by bracket depth.") { editor?.editor?.reindent() }],
            [AppCommand(menu: "Format", title: "Insert Table…", systemImage: "tablecells", isEnabled: !(tables == nil || project?.selectedBuffer == nil)) { tables?.insertPresented = true },
             AppCommand(menu: "Format", title: "Edit Table…", systemImage: "tablecells.badge.ellipsis", isEnabled: tables?.caretInTable == true) { tables?.beginEdit() }],
            [AppCommand(menu: "Format", title: "Move Section Up", systemImage: "arrow.up.square", shortcut: KeyboardShortcut(.upArrow, modifiers: [.control, .option]), isEnabled: project?.selectedBuffer?.isTypst == true && editor != nil) {
                 if let e = editor?.editor { e.moveSectionAtCaret(up: true) } else { NSSound.beep() }
             },
             AppCommand(menu: "Format", title: "Move Section Down", systemImage: "arrow.down.square", shortcut: KeyboardShortcut(.downArrow, modifiers: [.control, .option]), isEnabled: project?.selectedBuffer?.isTypst == true && editor != nil) {
                 if let e = editor?.editor { e.moveSectionAtCaret(up: false) } else { NSSound.beep() }
             }],
        ]
    }

    static func preview(_ ctx: AppCommandContext) -> [[AppCommand]] {
        let project = ctx.project
        return [
            [AppCommand(menu: "View", title: "Zoom In", systemImage: "plus.magnifyingglass", shortcut: KeyboardShortcut("+"), isEnabled: project != nil) { project?.preview.zoom(by: 1.25) },
             AppCommand(menu: "View", title: "Zoom Out", systemImage: "minus.magnifyingglass", shortcut: KeyboardShortcut("-"), isEnabled: project != nil) { project?.preview.zoom(by: 0.8) },
             AppCommand(menu: "View", title: "Fit Width", systemImage: "arrow.left.and.right", shortcut: KeyboardShortcut("0"), isEnabled: project != nil, isOn: project.map { $0.preview.fit == .width }) { project?.preview.fit = .width },
             AppCommand(menu: "View", title: "Fit Page", systemImage: "arrow.up.and.down.and.arrow.left.and.right", shortcut: KeyboardShortcut("9"), isEnabled: project != nil, isOn: project.map { $0.preview.fit == .page }) { project?.preview.fit = .page },
             AppCommand(menu: "View", title: "Two Pages", systemImage: "book.pages", shortcut: KeyboardShortcut("8"), isEnabled: project != nil, isOn: project.map { $0.preview.fit == .twoPages }) { project?.preview.fit = .twoPages }],
            [AppCommand(menu: "View", title: "Page Thumbnails", systemImage: "sidebar.squares.left", isEnabled: project != nil, isOn: project?.preview.showsThumbnails ?? false,
                        help: "Shows a strip of small pages beside the preview.") { project?.preview.showsThumbnails.toggle() },
             AppCommand(menu: "View", title: "Dark Preview Pages", systemImage: "circle.lefthalf.filled", isEnabled: project != nil, isOn: project?.preview.darkPages ?? false,
                        help: "Darkens the pages on screen only; exports keep their colors.") { project?.preview.darkPages.toggle() },
             AppCommand(menu: "View", title: "Start Presentation", systemImage: "play.rectangle", shortcut: KeyboardShortcut(.return, modifiers: [.command, .option]),
                        isEnabled: !(project?.preview.pages.isEmpty ?? true), help: "Shows the pages full screen, one at a time; arrow keys move, Escape ends.") {
                 if let project { PresentationSession.start(project, presenter: false, openWindow: ctx.openWindow) }
             },
             AppCommand(menu: "View", title: "Start Presentation with Presenter View", systemImage: "rectangle.on.rectangle",
                        shortcut: KeyboardShortcut(.return, modifiers: [.command, .option, .shift]), isEnabled: !(project?.preview.pages.isEmpty ?? true)) {
                 if let project { PresentationSession.start(project, presenter: true, openWindow: ctx.openWindow) }
             }],
            [AppCommand(menu: "View", title: "Preview Follows Cursor", systemImage: "text.cursor", isEnabled: project != nil, isOn: project?.preview.followsCursor ?? true) {
                if let project { project.preview.followsCursor.toggle() }
             },
             AppCommand(menu: "View", title: "Lock Preview Document", systemImage: "lock", isEnabled: project != nil, isOn: project?.previewLocked ?? true) {
                if let project { project.previewLocked.toggle() }
             }],
        ]
    }

    static func library(_ ctx: AppCommandContext) -> [[AppCommand]] {
        [[AppCommand(menu: "View", title: "Library…", systemImage: "books.vertical", shortcut: KeyboardShortcut("l", modifiers: [.command, .shift]), isEnabled: ctx.layout != nil) { ctx.layout?.library = .snippets },
          AppCommand(menu: "View", title: "Command Palette…", systemImage: "command", shortcut: KeyboardShortcut("p", modifiers: [.command, .shift]), isEnabled: ctx.layout != nil) { ctx.layout?.library = .commands }]]
    }

    static func editorView(_ ctx: AppCommandContext) -> [[AppCommand]] {
        let layout = ctx.layout, project = ctx.project, editor = ctx.editor
        let defaults = UserDefaults.standard
        let size = (defaults.object(forKey: SettingsKey.editorFontSize) as? Double) ?? EditorStyle.defaultSize
        return [
            [AppCommand(menu: "View", title: "Focus Mode", systemImage: "scope", shortcut: KeyboardShortcut(.return, modifiers: [.command, .shift]), isEnabled: layout != nil, isOn: layout?.focus ?? false) { layout?.toggleFocus() },
             AppCommand(menu: "View", title: "Split Editor", systemImage: "rectangle.split.2x1", shortcut: KeyboardShortcut("t", modifiers: [.command, .control]),
                        isEnabled: !(layout == nil || project == nil || layout?.focus == true), isOn: layout?.split ?? false) { if let project { layout?.toggleSplit(in: project) } },
             AppCommand(menu: "View", title: "Show Inspector", systemImage: "sidebar.trailing", shortcut: KeyboardShortcut("0", modifiers: [.command, .option]),
                        isEnabled: layout != nil, isOn: layout?.showInspector ?? false) { layout?.showInspector.toggle() },
             AppCommand(menu: "View", title: "Bottom Area", systemImage: "rectangle.bottomthird.inset.filled", shortcut: KeyboardShortcut("y", modifiers: [.command, .shift]),
                        isEnabled: layout != nil, isOn: layout?.bottom.isShown ?? false) { layout?.bottom.isShown.toggle() },
             AppCommand(menu: "View", title: "Minimap", systemImage: "sidebar.right", isOn: MinimapSetting.shared.isOn) { MinimapSetting.shared.isOn.toggle() },
             AppCommand(menu: "View", title: "Vim Mode", systemImage: "keyboard", isOn: defaults.bool(forKey: SettingsKey.vimMode)) {
                defaults.set(!defaults.bool(forKey: SettingsKey.vimMode), forKey: SettingsKey.vimMode)
             },
             AppCommand(menu: "View", title: "Bigger Text", systemImage: "textformat.size.larger", shortcut: KeyboardShortcut("+", modifiers: [.command, .option]), isEnabled: size < EditorStyle.sizes.upperBound) {
                defaults.set(min(size + 1, EditorStyle.sizes.upperBound), forKey: SettingsKey.editorFontSize)
             },
             AppCommand(menu: "View", title: "Smaller Text", systemImage: "textformat.size.smaller", shortcut: KeyboardShortcut("-", modifiers: [.command, .option]), isEnabled: size > EditorStyle.sizes.lowerBound) {
                defaults.set(max(size - 1, EditorStyle.sizes.lowerBound), forKey: SettingsKey.editorFontSize)
             },
             AppCommand(menu: "View", title: "Default Text Size", systemImage: "textformat.size", shortcut: KeyboardShortcut("0", modifiers: [.command, .control]), isEnabled: size != EditorStyle.defaultSize) {
                defaults.set(EditorStyle.defaultSize, forKey: SettingsKey.editorFontSize)
             }],
            // Folding acts on the editor with keyboard focus, like the Format menu.
            [AppCommand(menu: "View", title: "Fold Section", systemImage: "arrow.down.right.and.arrow.up.left", shortcut: KeyboardShortcut(.leftArrow, modifiers: [.command, .option]), isEnabled: editor != nil) { editor?.editor?.foldAtCaret() },
             AppCommand(menu: "View", title: "Unfold Section", systemImage: "arrow.up.left.and.arrow.down.right", shortcut: KeyboardShortcut(.rightArrow, modifiers: [.command, .option]), isEnabled: editor != nil) { editor?.editor?.unfoldAtCaret() },
             AppCommand(menu: "View", title: "Fold All Sections", systemImage: "rectangle.compress.vertical", shortcut: KeyboardShortcut(.leftArrow, modifiers: [.command, .option, .shift]), isEnabled: editor != nil) { editor?.editor?.foldAll() },
             AppCommand(menu: "View", title: "Unfold All Sections", systemImage: "rectangle.expand.vertical", shortcut: KeyboardShortcut(.rightArrow, modifiers: [.command, .option, .shift]), isEnabled: editor != nil) { editor?.editor?.unfoldAll() }],
        ] + assistant(ctx)
    }

    static func assistant(_ ctx: AppCommandContext) -> [[AppCommand]] {
        let assistant = ctx.assistant, editor = ctx.editor
        return [[AppCommand(menu: "View", title: "Show Assistant", systemImage: "sparkles", isEnabled: !(assistant == nil || editor == nil || ctx.layout?.focus == true),
                            isOn: assistant?.mode == .assistant) { if let editor { assistant?.toggle(editor: editor) } },
                 AppCommand(menu: "View", title: "New Conversation", systemImage: "square.and.pencil", isEnabled: assistant != nil) {
                     if let assistant, let editor, assistant.mode != .assistant { assistant.toggle(editor: editor) }
                     assistant?.newConversation()
                 }]]
    }

    static func navigate(_ ctx: AppCommandContext) -> [[AppCommand]] {
        let project = ctx.project
        let typst = project?.selectedBuffer?.isTypst == true
        return [[AppCommand(menu: "Navigate", title: "Jump to Definition", systemImage: "arrow.right.circle", shortcut: JumpShortcut.defaultShortcut, isEnabled: typst) {
                     guard let project else { return }
                     // With a hover card open on a jumpable name (its hint names this shortcut), follow that name, else the caret's.
                     if let t = References.hoverTarget { Task { await References.jump(project, buffer: t.buffer, at: t.offset) } } else { Task { await References.jump(project) } }
                 },
                 AppCommand(menu: "Navigate", title: "Find References", systemImage: "list.bullet.rectangle", shortcut: KeyboardShortcut("r", modifiers: [.command, .control]), isEnabled: typst) { if let project { Task { await References.findReferences(project) } } },
                 AppCommand(menu: "Navigate", title: "Show Quick Fixes", systemImage: "lightbulb", shortcut: KeyboardShortcut(".", modifiers: [.command]), isEnabled: typst && ctx.editor != nil) { if let e = ctx.editor?.editor { e.showQuickFixesAtCaret() } else { NSSound.beep() } },
                 // (`EditorActions.editor` is a weak, unobserved reference: the menu would never re-enable on it.)
                 AppCommand(menu: "Navigate", title: "Rename Symbol…", systemImage: "tag", shortcut: KeyboardShortcut("e", modifiers: [.command, .control]), isEnabled: typst) { if let project { Task { await References.rename(project) } } }],
                [AppCommand(menu: "Navigate", title: "Go Back", systemImage: "chevron.left", shortcut: KeyboardShortcut(.leftArrow, modifiers: [.command, .control]), isEnabled: project?.navigationHistory.canGoBack == true) { project?.goBack() },
                 AppCommand(menu: "Navigate", title: "Go Forward", systemImage: "chevron.right", shortcut: KeyboardShortcut(.rightArrow, modifiers: [.command, .control]), isEnabled: project?.navigationHistory.canGoForward == true) { project?.goForward() }],
                [AppCommand(menu: "Navigate", title: "Open Quickly…", systemImage: "magnifyingglass", shortcut: KeyboardShortcut("o", modifiers: [.command, .shift]),
                            isEnabled: ctx.layout != nil) { ctx.layout?.quickOpen = .files },
                 AppCommand(menu: "Navigate", title: "Go to Line…", systemImage: "arrow.right.to.line", shortcut: KeyboardShortcut("l"),
                            isEnabled: !(ctx.layout == nil || ctx.editor == nil || project?.selectedBuffer == nil)) { ctx.layout?.quickOpen = .line }],
                [AppCommand(menu: "Navigate", title: "Toggle Bookmark", systemImage: "bookmark", shortcut: KeyboardShortcut("b", modifiers: [.command, .option]), isEnabled: ctx.editor != nil) { ctx.editor?.editor?.toggleBookmarkAtCaret() },
                 AppCommand(menu: "Navigate", title: "Add File Bookmark", systemImage: "bookmark.square", isEnabled: project?.selectedFile.map { project?.fileBookmark($0) == nil } == true) { if let f = project?.selectedFile { project?.addFileBookmark(f) } },
                 AppCommand(menu: "Navigate", title: "Next Bookmark", systemImage: "chevron.down", shortcut: KeyboardShortcut(.downArrow, modifiers: [.command, .control]), isEnabled: project?.bookmarks.isEmpty == false) { jumpToBookmark(ctx, forward: true) },
                 AppCommand(menu: "Navigate", title: "Previous Bookmark", systemImage: "chevron.up", shortcut: KeyboardShortcut(.upArrow, modifiers: [.command, .control]), isEnabled: project?.bookmarks.isEmpty == false) { jumpToBookmark(ctx, forward: false) }],
                // ⌘1…⌘6; Changes stays last, so hiding it (source control off) leaves no gap in the numbers.
                SidebarTab.allCases.enumerated().filter { $0.element != .changes || UserDefaults.standard.object(forKey: SettingsKey.sourceControl) as? Bool ?? true }.map { i, tab in
                    AppCommand(menu: "Navigate", title: "Show \(tab.title) Navigator", idTitle: "Show \(tab.title) Navigator", systemImage: tab.symbol, shortcut: KeyboardShortcut(KeyEquivalent(Character("\(i + 1)"))), isEnabled: ctx.sidebar != nil) { ctx.sidebar?.tab = tab }
                }]
    }

    /// Everything the palette offers: all menu commands except the palette itself and Close Window.
    /// `forPalette: false` is the Shortcuts catalog: Close Window included, shortcuts still the defaults from code.
    static func all(_ ctx: AppCommandContext, forPalette: Bool = true) -> [AppCommand] {
        let groups = newProject(ctx) + open(ctx) + fileItems(ctx) + save(ctx) + tabs(ctx) + print(ctx) + export(ctx) + snapshots(ctx) + multiCursor() + format(ctx)
            + preview(ctx) + editorView(ctx) + navigate(ctx) + tabSwitching(ctx) + git(ctx)
        return groups.flatMap { $0 }.filter { !forPalette || $0.id != "File/Close Window" }
            .map { var c = $0; c.help = helpTexts[c.id]; if forPalette { c.shortcut = ShortcutStore.shared.resolved(c) }; return c }
    }

    /// Help sentences by command id (see `AppCommand.help`).
    static let helpTexts: [String: LocalizedStringResource] = gitHelpTexts.merging([
        "File/New Project…": "Creates a new Typst project in a folder you choose and opens it in a new window.",
        "File/New Project from Template…": "Opens the template gallery to start a project from a template.",
        "File/Open…": "Chooses an existing project folder and opens it in a window.",
        "File/New File…": "Creates a new file in the project and starts naming it in the sidebar.",
        "File/Connect Zotero…": "Fills a .bib file of the project from your Zotero library and keeps it in sync.",
        "File/New Folder…": "Creates a new folder in the project and starts naming it in the sidebar.",
        "File/Rename": "Renames the file or folder selected in the sidebar.",
        "File/Duplicate": "Makes a copy of the selected file or folder next to the original.",
        "File/Move to Trash": "Moves the selected file or folder to the Trash; only while the file list has focus.",
        "File/Save": "Writes all unsaved changes in the project to disk.",
        "File/New Tab…": "Opens Open Quickly to show a project file in a new tab.",
        "File/Close Tab": "Closes the current tab, or the window when no tab is open.",
        "File/Close Window": "Closes the project window.",
        "File/Snapshots…": "Opens the project's saved snapshots to browse or restore earlier versions.",
        "Window/Show Next Tab": "Switches to the tab on the right of the current one.",
        "Window/Show Previous Tab": "Switches to the tab on the left of the current one.",
        "File/Print…": "Prints the project's pages, or saves them as a PDF from the print panel.",
        "Export/PDF…": "Compiles the project and saves it as a PDF file.",
        "Export/PDF/A-2b for Archiving…": "Saves the project as a PDF/A-2b file, a standard for long-term archiving.",
        "Export/PDF/A-3b for Archiving…": "Saves the project as a PDF/A-3b file, an archiving standard that allows embedded files.",
        "Export/PNG Images…": "Saves every page of the project as a PNG image.",
        "Export/SVG Images…": "Saves every page of the project as an SVG image.",
        "Export/Project Archive (ZIP)…": "Saves the project folder as a ZIP file, without hidden files such as .git.",
        "Format/Bold": "Wraps the selection in *strong* emphasis, or removes it.",
        "Format/Italic": "Wraps the selection in _emphasis_, or removes it.",
        "Format/Underline": "Wraps the selection in #underline[…], or removes it.",
        "Format/Bullet List": "Turns the selected lines into a bulleted list, or back into plain lines.",
        "Format/Numbered List": "Turns the selected lines into a numbered list, or back into plain lines.",
        "Format/Move Section Up": "Moves the section around the caret, with its subsections, above the previous section of its level.",
        "Format/Move Section Down": "Moves the section around the caret, with its subsections, below the next section of its level.",
        "Format/Math": "Wraps the selection in $…$ as a math formula, or removes it.",
        "Format/Insert Citation…": "Opens the citation picker to insert a reference from the project's bibliography.",
        "Format/Insert Table…": "Opens the table editor to insert a new table at the caret.",
        "Format/Edit Table…": "Opens the table under the caret in the visual table editor.",
        "View/Show Inspector": "Shows file, document and selection details in a column on the right.",
        "View/Zoom In": "Enlarges the preview by 25 percent.",
        "View/Zoom Out": "Shrinks the preview by 20 percent.",
        "View/Start Presentation with Presenter View": "Shows the slides full screen on a second display and, on this one, a window with the next slide, speaker notes, the slide number and a timer. With one display only that window opens, to rehearse.",
        "View/Fit Width": "Resets the preview zoom so the page fits the preview's width.",
        "View/Preview Follows Cursor": "Scrolls the preview to the position of the editor's caret as you move it.",
        "View/Lock Preview Document": "Keeps previewing the main document instead of the file you are editing.",
        "View/Library…": "Opens the library to insert snippets, images, symbols and fonts, or to run commands.",
        "View/Command Palette…": "Opens the library on its commands to search and run any menu command.",
        "View/Focus Mode": "Hides the sidebar, preview and second pane and centers the text.",
        "View/Split Editor": "Shows a second editor pane next to the first, with its own tabs.",
        "View/Minimap": "Shows a scaled-down overview of the whole file at the editor's right edge; click or drag it to scroll.",
        "View/Bigger Text":"Increases the editor's font size by one point.",
        "View/Smaller Text": "Decreases the editor's font size by one point.",
        "View/Default Text Size": "Resets the editor's font size to the default.",
        "View/Vim Mode": "Edits with Vim's modes and keys: Esc for Normal mode, i to insert, v to select, : for w, q and wq.",
        "View/Fold Section": "Collapses the heading section the caret is in.",
        "View/Unfold Section": "Expands the collapsed section at the caret.",
        "View/Fold All Sections": "Collapses every heading section in the editor.",
        "View/Unfold All Sections": "Expands every collapsed section in the editor.",
        "View/Show Assistant": "Switches the sidebar and editor to the assistant chat, or back to the navigator and editor.",
        "View/New Conversation": "Starts a new conversation with the assistant.",
        "Navigate/Jump to Definition": "Jumps from a reference, variable, function or import to where it is defined.",
        "Navigate/Find References": "Lists every use of the label, variable or function under the caret across the project.",
        "Navigate/Show Quick Fixes": "Offers fixes for the compiler issue at the caret, such as a similar label or name, a missing import or a nearby file.",
        "Navigate/Open Quickly…": "Finds a file, heading, label, function, variable, bibliography entry or Typst function by a few of its letters; name:line opens a file at a line.",
        "Navigate/Go to Line…": "Moves the caret to a line: 42, 42:7 for a column, or +10 and -10 relative to the current line.",
        "Navigate/Rename Symbol…": "Renames the label, variable or function under the caret everywhere it is used.",
        "Navigate/Toggle Bookmark": "Bookmarks the caret's line, or removes its bookmark; the Bookmarks navigator lists them all.",
        "Navigate/Add File Bookmark": "Bookmarks the shown file as a whole; it follows renames and goes when the file is trashed.",
        "Navigate/Next Bookmark": "Moves the caret to the next bookmarked line, across files.",
        "Navigate/Previous Bookmark": "Moves the caret to the previous bookmarked line, across files.",
        "Navigate/Show Bookmarks Navigator": "Shows the project's bookmarked lines in the sidebar.",
    ]) { a, _ in a }

    /// Renders groups as menu items with Dividers between the groups.
    @ViewBuilder static func items(_ groups: [[AppCommand]]) -> some View {
        ForEach(Array(groups.enumerated()), id: \.offset) { i, group in
            if i > 0 { Divider() }
            ForEach(group) { c in
                let localization: KeyboardShortcut.Localization = ShortcutStore.shared.adaptsToKeyboard ? .automatic : .custom
                let shortcut = ShortcutStore.shared.resolved(c).map { KeyboardShortcut($0.key, modifiers: $0.modifiers, localization: localization) }
                if let isOn = c.isOn {
                    Toggle(isOn: Binding(get: { isOn }, set: { _ in c.action() })) { Label(c.title, systemImage: c.systemImage) }
                        .keyboardShortcut(shortcut)
                        .disabled(!c.isEnabled)
                } else {
                    Button(c.title, systemImage: c.systemImage, action: c.action)
                        .keyboardShortcut(shortcut)
                        .disabled(!c.isEnabled)
                }
            }
        }
    }

    private static func closeTab(_ ctx: AppCommandContext) {
        guard let project = ctx.project else { return NSApp.keyWindow?.performClose(nil) ?? () }
        if ctx.secondPaneFocused, let layout = ctx.layout, let f = layout.secondFile, layout.tabs.contains(f) {
            layout.closeSecondTab(f, in: project)
        } else if let f = project.selectedFile, project.tabs.contains(f) {
            project.closeTab(f)
        } else {
            NSApp.keyWindow?.performClose(nil)
        }
    }

    private static func jumpToBookmark(_ ctx: AppCommandContext, forward: Bool) {
        guard let project = ctx.project else { return }
        let line = ctx.editor?.editor?.caretLine ?? (forward ? -1 : Int.max)
        if let b = project.adjacentBookmark(from: project.selectedFile, line: line, forward: forward) { project.reveal(b) }
    }

    private static func moveTab(_ ctx: AppCommandContext, _ offset: Int) {
        guard let project = ctx.project else { return }
        if ctx.secondPaneFocused, let layout = ctx.layout {
            if let next = layout.tabs.neighbour(of: layout.secondFile, by: offset) { layout.showSecond(next, in: project) }
        } else if let next = project.tabs.neighbour(of: project.selectedFile, by: offset) {
            project.selectedFile = next
        }
    }
}
