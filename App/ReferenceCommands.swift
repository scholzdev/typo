import AppKit
import SwiftUI
import TypoKit
import TypstEngine

struct ReferenceCommands: Commands {
    let recents: RecentProjects
    private let focus = FocusedCommandContext()

    private var context: AppCommandContext { focus.context(recents: recents) }

    var body: some Commands {
        let ctx = context
        CommandMenu("Navigate") {
            AppCommands.items(AppCommands.navigate(ctx))
        }
    }
}

@MainActor enum References {
    /// The jumpable name under the visible hover card; Jump to Definition follows it instead of the caret.
    static var hoverTarget: (buffer: Buffer, offset: Int)?

    /// True when `offset` of the buffer is on a label or reference (⌘-click then jumps instead of placing the caret).
    static func isOnLabel(_ buffer: Buffer, at offset: Int) -> Bool {
        buffer.isTypst && LabelIndex.build([(buffer.path, buffer.storage.string)]).hit(in: buffer.path, at: offset) != nil
    }

    /// True when `offset` is on a label, a binding, a use of one or an import path (⌘-click then jumps).
    static func isNavigable(_ buffer: Buffer, at offset: Int) -> Bool {
        guard buffer.isTypst else { return false }
        let files = [(buffer.path, buffer.storage.string)]
        return LabelIndex.build(files).hit(in: buffer.path, at: offset) != nil || BindingIndex.build(files).hasSite(in: buffer.path, at: offset)
            || pathTarget(buffer, at: offset) != nil
    }

    /// The existing project file named by the path string at `offset`.
    private static func pathTarget(_ buffer: Buffer, at offset: Int) -> (range: NSRange, target: RelPath)? {
        PathReferences.target(in: buffer.storage.string, of: buffer.path, at: offset, existing: Set(buffer.project.allFiles))
    }

    private static func target(_ project: Project, buffer: Buffer?) -> Buffer? {
        buffer ?? project.focusedEditorFile.flatMap(project.buffer(for:)) ?? project.selectedBuffer
    }

    static func jump(_ project: Project, buffer: Buffer? = nil, at offset: Int? = nil) async {
        guard let buffer = target(project, buffer: buffer) else { return }
        let file = buffer.path
        let offset = offset ?? buffer.selection.location
        let index = await project.labelIndex()
        if let hit = index.hit(in: file, at: offset) {
            guard let (site, count) = index.target(of: hit.name) else {
                NSSound.beep()
                return toast("No definition for @\(hit.name)")
            }
            project.show(site.file, range: site.token, flash: true)
            if count > 1 { toast("\(count) definitions of <\(hit.name)>; showing the first") }
            return
        }
        switch await project.definition(in: file, at: offset) {
        case .source(let f, let r):
            // The compiler stops at `import "a.typ": f`; the binding index follows the import item into a.typ.
            let symbol = await project.bindingIndex().symbol(in: f, at: r.location)
            if let symbol, symbol.file != f || symbol.defRange.location != r.location {
                return project.show(symbol.file, range: symbol.defRange, flash: true)
            }
            return project.show(f, range: r, flash: true)
        case .file(let f): return project.openPermanently(f)
        case .builtin(let doc):
            // Nothing to jump to: the full documentation instead (Quick Help, ⌥-click, is the short form).
            guard !doc.docs.isEmpty, let (caret, window) = caretRect(offset) else { return toast("`\(doc.name)` is built into Typst") }
            return DocsPanel.shared.show(doc: doc, caret: caret, in: window)
        case .package(let spec): return toast("Defined in package \(spec)")
        case nil: break
        }
        if let symbol = await project.bindingIndex().symbol(in: file, at: offset) {
            project.show(symbol.file, range: symbol.defRange, flash: true)
        } else if let (_, path) = pathTarget(buffer, at: offset) {
            // No sidebar Quick Look from here (its model is view state): images and PDFs open in the default app.
            if FileKind.isText(path.raw) { project.openPermanently(path) } else { NSWorkspace.shared.open(project.url(for: path)) }
        } else {
            NSSound.beep()
        }
    }

    /// Quick Help (⌥-click, as in Xcode): the signature with all parameters, the one-line summary and, for a built-in, the web link.
    static func quickHelp(_ project: Project, buffer: Buffer, at offset: Int) async {
        let file = buffer.path
        let signature = await project.signature(in: file, at: offset)
        let tip = await tooltip(project, file, offset)
        // Short by design: no details or examples (⌘-click on a built-in shows those), only the link to them.
        var url: URL?
        if case .builtin(let d)? = await project.definition(in: file, at: offset) { url = d.url }
        guard tip != nil || signature != nil, let (caret, window) = caretRect(offset) else { return NSSound.beep() }
        DocsPanel.shared.show(doc: BuiltinDoc(name: "", docs: "", url: url), signature: signature, tip: tip, caret: caret, in: window)
    }

    /// The hover tooltip at `offset`: for a function its signature with every parameter, then a one-line summary.
    private static func tooltip(_ project: Project, _ file: RelPath, _ offset: Int) async -> AttributedString? {
        switch await project.hover(in: file, at: offset)?.tooltip {
        case .text(let a)?, .code(let a)?: a
        case nil: nil
        }
    }

    /// The screen rect of `offset` in the key window's text view, where panels are anchored.
    private static func caretRect(_ offset: Int) -> (NSRect, NSWindow)? {
        guard let tv = NSApp.keyWindow?.firstResponder as? NSTextView, let window = tv.window else { return nil }
        let r = NSRange(location: min(offset, (tv.string as NSString).length), length: 0)
        return (tv.firstRect(forCharacterRange: r, actualRange: nil), window)
    }

    static func findReferences(_ project: Project) async {
        guard let buffer = target(project, buffer: nil) else { return }
        let file = buffer.path, offset = buffer.selection.location
        var sites: [(site: RelPath, range: NSRange, isDefinition: Bool)] = []
        var name = ""
        let labels = await project.labelIndex()
        if let hit = labels.hit(in: file, at: offset) {
            name = hit.name
            // Labels and bibliography keys both count as definitions here (a citation key may also be a label).
            let defs = (labels.definitions[hit.name] ?? []) + (labels.bibKeys[hit.name] ?? [])
            sites = defs.map { ($0.file, $0.token, true) } + (labels.references[hit.name] ?? []).map { ($0.file, $0.token, false) }
        } else {
            let index = await project.bindingIndex()
            guard let symbol = index.symbol(in: file, at: offset) else { return NSSound.beep() }
            name = symbol.name
            sites = index.sites(of: symbol).map { ($0.file, $0.range, $0 == symbol.site) }
        }
        guard !sites.isEmpty else { return NSSound.beep() }
        let rows = ReferenceRow.make(sites, project: project)
        let refs = rows.filter { !$0.isDefinition }.count, defs = rows.count - refs
        let title = defs == 1 ? "\(refs) reference\(refs == 1 ? "" : "s") to “\(name)”" : "\(defs) definitions, \(refs) reference\(refs == 1 ? "" : "s") to “\(name)”"
        guard let tv = NSApp.keyWindow?.firstResponder as? NSTextView, let window = tv.window else { return }
        let caret = tv.firstRect(forCharacterRange: tv.selectedRange(), actualRange: nil)
        let results = ReferenceResults.of(project)
        results.set(title: title, rows: rows)
        ReferencePanel.shared.show(title: title, rows: rows, caret: caret, in: window, choose: { row in
            project.show(row.file, range: row.range, flash: true)
        }, showInSidebar: results.reveal)
    }

    /// The jumpable name under `offset` for ⌘-hover: a label or reference token, else the identifier around it.
    /// Cached per buffer text, since the pointer moves often and the scans parse the whole file.
    static func navigableRange(_ buffer: Buffer, at offset: Int) -> NSRange? {
        guard buffer.isTypst else { return nil }
        let text = buffer.storage.string
        if hoverCache?.buffer !== buffer || hoverCache?.text != text {
            hoverCache = (buffer, text, LabelIndex.build([(buffer.path, text)]), BindingIndex.build([(buffer.path, text)]))
        }
        guard let cache = hoverCache else { return nil }
        if let hit = cache.labels.hit(in: buffer.path, at: offset) { return hit.site.token }
        guard cache.bindings.hasSite(in: buffer.path, at: offset) else { return pathTarget(buffer, at: offset)?.range }
        return identifier(in: text as NSString, around: offset)
    }

    private static var hoverCache: (buffer: Buffer, text: String, labels: LabelIndex, bindings: BindingIndex)?

    /// The run of identifier characters (letters, digits, `_`, `-`) touching `offset`.
    private static func identifier(in ns: NSString, around offset: Int) -> NSRange? {
        func isIdent(_ i: Int) -> Bool {
            guard i >= 0, i < ns.length, let u = Unicode.Scalar(ns.character(at: i)) else { return false }
            return CharacterSet.alphanumerics.contains(u) || u == "_" || u == "-"
        }
        var start = offset, end = offset
        while isIdent(start - 1) { start -= 1 }
        while isIdent(end) { end += 1 }
        // A trailing hyphen is never part of a name: `a-` before a minus sign.
        while end > start, ns.character(at: end - 1) == 45 { end -= 1 }
        return end > start ? NSRange(location: start, length: end - start) : nil
    }

    static func rename(_ project: Project) async {
        guard !LicenseStore.shared.readOnly else { return }
        guard let file = project.selectedFile, let buffer = project.selectedBuffer, let window = NSApp.keyWindow else { return }
        let offset = buffer.selection.location
        let sheet = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        let close = { window.endSheet(sheet) }
        let labels = await project.labelIndex()
        if let hit = labels.hit(in: file, at: offset) {
            sheet.contentViewController = NSHostingController(rootView: RenameView(title: "Rename “\(hit.name)”", old: hit.name, summary: labels.renameSummary(of: hit.name), validate: { labels.validate($0, replacing: hit.name) }, cancel: close) { new in
                close()
                do {
                    for (f, edits) in labels.rename(hit.name, to: new) { try await project.edit(f, edits, actionName: "Rename Label") }
                } catch { showAlert("Couldn’t Rename", "\(error)") }
            })
            return window.beginSheet(sheet, completionHandler: nil)
        }
        let index = await project.bindingIndex()
        guard let symbol = index.symbol(in: file, at: offset) else { return NSSound.beep() }
        guard index.isRenameable(symbol) else { return toast("This name comes from the file name; rename the file instead.") }
        let snapshot = buffer.storage.string
        sheet.contentViewController = NSHostingController(rootView: RenameView(title: "Rename “\(symbol.name)”", old: symbol.name, summary: index.renameSummary(of: symbol), validate: { index.validate($0, for: symbol) }, cancel: close) { new in
            close()
            var index = index, symbol = symbol
            if buffer.storage.string != snapshot {
                index = await project.bindingIndex()
                guard let s = index.symbol(in: file, at: offset), s.name == symbol.name else { return NSSound.beep() }
                symbol = s
            }
            do {
                for (f, edits) in index.rename(symbol, to: new) { try await project.edit(f, edits, actionName: "Rename") }
            } catch { showAlert("Couldn’t Rename", "\(error)") }
        })
        window.beginSheet(sheet, completionHandler: nil)
    }

    /// A short note beside the caret, gone after two seconds.
    private static func toast(_ message: String) {
        guard let tv = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
        guard tv.window != nil else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: Text(message).padding(10))
        popover.show(relativeTo: tv.viewRect(forCharacterRange: tv.selectedRange()), of: tv, preferredEdge: .maxY)
        Task { try? await Task.sleep(for: .seconds(2)); popover.close() }
    }
}

struct RenameView: View {
    let title: String
    let old: String
    let summary: String
    let validate: (String) -> String?
    let cancel: () -> Void
    let apply: (String) async -> Void
    @State private var name: String

    init(title: String, old: String, summary: String, validate: @escaping (String) -> String?, cancel: @escaping () -> Void, apply: @escaping (String) async -> Void) {
        self.title = title; self.old = old; self.summary = summary; self.validate = validate; self.cancel = cancel; self.apply = apply
        _name = State(initialValue: old)
    }

    private var problem: String? { validate(name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            TextField("New name", text: $name).frame(width: 280).onSubmit(commit)
            Text(summary).font(.callout).foregroundStyle(.secondary)
            Text(problem ?? " ").font(.callout).foregroundStyle(.red)
            HStack {
                Spacer()
                SheetButtons(ok: "Rename", disabled: problem != nil, cancel: cancel, action: commit)
            }
        }
        .padding(20)
    }

    private func commit() { if problem == nil { Task { await apply(name) } } }
}
