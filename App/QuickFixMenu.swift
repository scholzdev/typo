import AppKit
import TypoKit
import TypstEngine

/// The Quick Fixes menu (⌘., the lightbulb on a diagnostic pill, the context menu, the Issues tab).
@MainActor enum QuickFixMenu {
    /// Fixable diagnostics of `file` at `offset`: those whose range contains or touches it, else those on the same line.
    static func fixableDiagnostics(project: Project, file: RelPath, at offset: Int, text: NSString) -> [Diagnostic] {
        let fixable = (project.diagnostics(in: file) + project.lintHints(in: file)).filter(QuickFixes.mayFix)
        func range(_ d: Diagnostic) -> NSRange? { if case .project(let l) = d.origin { l.range } else { nil } }
        let touching = fixable.filter { d in range(d).map { $0.location <= offset && offset <= NSMaxRange($0) } ?? false }
        if !touching.isEmpty { return touching }
        guard offset <= text.length else { return [] }
        let line = text.lineRange(for: NSRange(location: offset, length: 0))
        return fixable.filter { d in range(d).map { $0.location >= line.location && $0.location < NSMaxRange(line) } ?? false }
    }

    /// The diagnostics at `offset` with the fixes of each; diagnostics without a fix are left out.
    static func fixes(project: Project, file: RelPath, at offset: Int) async -> [(Diagnostic, [QuickFix])] {
        guard let text = project.buffer(for: file)?.storage.string as NSString? else { return [] }
        var out: [(Diagnostic, [QuickFix])] = []
        for d in fixableDiagnostics(project: project, file: file, at: offset, text: text) {
            let f = await project.quickFixes(for: d)
            if !f.isEmpty { out.append((d, f)) }
        }
        return out
    }

    /// Pops the menu up at `point` in `view` (screen coordinates when `view` is nil); beeps when there is nothing to offer and no details.
    static func show(_ fixes: [(Diagnostic, [QuickFix])], project: Project, in view: NSView?, at point: NSPoint, refactorings: [Refactoring] = [], apply applyRefactoring: ((Refactoring) -> Void)? = nil, details: (@MainActor () -> Void)? = nil) {
        guard !fixes.isEmpty || !refactorings.isEmpty else { return NSSound.beep() }
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (n, (d, list)) in fixes.enumerated() {
            if n > 0 { menu.addItem(.separator()) }
            let head = NSMenuItem(title: d.message.count > 60 ? String(d.message.prefix(59)) + "…" : d.message, action: nil, keyEquivalent: "")
            head.isEnabled = false
            menu.addItem(head)
            for fix in list { menu.addItem(item(fix.title) { apply(fix, project: project) }) }
        }
        if let applyRefactoring, !refactorings.isEmpty {
            if !fixes.isEmpty { menu.addItem(.separator()) }
            let head = NSMenuItem(title: String(localized: "Refactor"), action: nil, keyEquivalent: "")
            head.isEnabled = false
            menu.addItem(head)
            for r in refactorings { menu.addItem(item(r.title, symbol: "wand.and.stars", tint: nil) { applyRefactoring(r) }) }
        }
        if let details {
            menu.addItem(.separator())
            menu.addItem(item(String(localized: "Show Details"), symbol: "info.circle", tint: nil) { details() })
        }
        menu.popUp(positioning: nil, at: point, in: view)
    }

    private static func item(_ title: String, symbol: String = "lightbulb.fill", tint: NSColor? = .systemYellow, run: @escaping @MainActor () -> Void) -> NSMenuItem {
        let action = MenuAction(run)
        let item = NSMenuItem(title: title, action: #selector(MenuAction.fire), keyEquivalent: "")
        item.target = action
        item.representedObject = action                       // keeps it alive as long as the menu
        var image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        if let tint { image = image?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [tint])) }
        item.image = image
        return item
    }

    static func apply(_ fix: QuickFix, project: Project) {
        Task {
            do {
                for (file, edits) in fix.edits { try await project.edit(file, edits, actionName: String(localized: "Quick Fix")) }
                if let selection = fix.selection, let file = fix.edits.keys.first { project.show(file, range: selection) }
            } catch {
                showAlert("Couldn’t Apply Fix", error)
            }
        }
    }

    /// The Issues tab: the menu for one diagnostic at the pointer.
    static func show(for d: Diagnostic, project: Project) {
        Task {
            let fixes = await project.quickFixes(for: d)
            show(fixes.isEmpty ? [] : [(d, fixes)], project: project, in: nil, at: NSEvent.mouseLocation)
        }
    }

    private final class MenuAction: NSObject {
        let run: @MainActor () -> Void
        init(_ run: @escaping @MainActor () -> Void) { self.run = run }
        @MainActor @objc func fire() { run() }
    }
}

extension EditorView.Coordinator {
    /// The menu for the diagnostics at `offset`, popped up at `point` in `view`. `details` adds a "Show Details" item that reveals the hover card.
    func showQuickFixes(at offset: Int, from view: NSView, point: NSPoint, details: NSRange? = nil) {
        guard let project, let file = buffer?.path else { return }
        Task {
            let fixes = await QuickFixMenu.fixes(project: project, file: file, at: offset)
            var show: (@MainActor () -> Void)?
            if let range = details { show = { self.showHover(forDiagnosticAt: range) } }
            // A diagnostic pill (`details`) is about that diagnostic, not the selection.
            let refactorings = details == nil ? textView.flatMap { buffer?.refactorings(selection: $0.selectedRange()) } ?? [] : []
            if fixes.isEmpty, refactorings.isEmpty, let show { return show() }
            QuickFixMenu.show(fixes, project: project, in: view, at: point, refactorings: refactorings,
                              apply: { [weak self = self] in self?.apply($0) }, details: show)
        }
    }

    func apply(_ r: Refactoring) {
        replace(r.range, with: r.snippet.text, selecting: r.snippet.selection(insertedAt: r.range.location),
                session: r.snippet.placeholders.isEmpty ? nil : (r.snippet, r.range.location))
    }

    /// ⌘.: the menu below the caret.
    func showQuickFixesAtCaret() {
        guard let tv = textView else { return }
        let caret = tv.selectedRange().location
        let r = tv.viewRect(forCharacterRange: NSRange(location: caret, length: 0))
        showQuickFixes(at: caret, from: tv, point: NSPoint(x: r.minX, y: r.maxY + 2))
    }
}
