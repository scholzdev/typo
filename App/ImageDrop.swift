import AppKit
import TypoKit
import TypstEngine

/// Image files dropped on, or images pasted into, a Typst file become figures (design/14e). Multi-line text pastes
/// may be re-indented ("Re-indent on paste"). Every other drop and paste keeps NSTextView's own behavior.
extension EditorTextView {
    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        let types = super.acceptableDragTypes
        return types.contains(.fileURL) ? types : types + [.fileURL]
    }

    private var imageTarget: EditorView.Coordinator? {
        (delegate as? EditorView.Coordinator).flatMap { $0.buffer?.isTypst == true ? $0 : nil }
    }

    /// The pasteboard's file URLs when there are some and all of them are images.
    private static func imageFiles(_ pb: NSPasteboard) -> [URL]? {
        let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return !urls.isEmpty && urls.allSatisfy({ ImageInsert.isImage($0.path) }) ? urls : nil
    }

    /// Bitmap data (a screenshot) as PNG; only when there is no text, since apps often put both.
    private static func pastedImage(_ pb: NSPasteboard) -> Data? {
        guard pb.availableType(from: [.string]) == nil else { return nil }
        if let png = pb.data(forType: .png) { return png }
        guard let tiff = pb.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let op = super.draggingEntered(sender)
        return imageTarget != nil && Self.imageFiles(sender.draggingPasteboard) != nil ? .copy : op
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let op = super.draggingUpdated(sender)
        return imageTarget != nil && Self.imageFiles(sender.draggingPasteboard) != nil ? .copy : op
    }

    /// Copies synchronously: the sandbox grants access to dropped files only during the drop.
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let c = imageTarget, let urls = Self.imageFiles(sender.draggingPasteboard) else { return super.performDragOperation(sender) }
        let at = characterIndexForInsertion(at: convert(sender.draggingLocation, from: nil))
        c.insertImages(.files(urls), replacing: NSRange(location: at, length: 0))
        return true
    }

    override func paste(_ sender: Any?) {
        if multiPaste() { return }
        let pb = NSPasteboard.general
        if let c = imageTarget, let urls = Self.imageFiles(pb) { return c.insertImages(.files(urls), replacing: selectedRange()) }
        if let c = imageTarget, let png = Self.pastedImage(pb) { return c.insertImages(.data(png), replacing: selectedRange()) }
        if let c = delegate as? EditorView.Coordinator, let text = pb.string(forType: .string), c.pasteReindented(text) { return }
        super.paste(sender)
    }
}

extension EditorView.Coordinator {
    enum ImageSource { case files([URL]), data(Data) }

    /// Puts the images into the project (see `Project.importImages`) and inserts their code as one undoable edit.
    func insertImages(_ source: ImageSource, replacing range: NSRange) {
        guard let project, let buffer else { return }
        let paths: [RelPath], created: [RelPath]
        do {
            switch source {
            case .files(let urls): (paths, created) = try project.importImages(urls)
            case .data(let png): paths = [try project.addPastedImage(png)]; created = paths
            }
        } catch {
            return showAlert("Couldn’t Add the Image", error.localizedDescription)
        }
        Task {
            let labels = await project.labelIndex()
            guard let tv = textView, tv.string.utf16.count >= NSMaxRange(range) else { return }
            // A figure inside a figure makes no sense: inside one's parentheses it is `image(…)`, inside its body `#image(…)`.
            let inFigure = FigureInfo.at(range.location, in: tv.string) != nil
            var mode = buffer.mode(at: range.location)
            if inFigure && mode == .markup { mode = .math }
            let snippet = ImageInsert.snippet(paths.map { ImageInsert.relativePath(from: buffer.path, to: $0) }, mode: mode) {
                labels.definitions[$0] != nil || labels.bibKeys[$0] != nil
            }
            // Same undo group as the insertion (no await between): one Cmd-Z removes the code and trashes the copies.
            if !created.isEmpty { Self.registerImageUndo({ created.map { ($0, nil) } }, project: project, in: buffer.undoManager) }
            if mode == .markup {
                let placed = TableCode.placement(of: snippet, in: tv.string, replacing: range)
                replace(range, with: placed.replacement, selecting: placed.selection, session: (placed.snippet, placed.at))
            } else {
                replace(range, with: snippet.text, selecting: snippet.selection(insertedAt: range.location), session: (snippet, range.location))
            }
        }
    }

    typealias ImageFiles = [(path: RelPath, trashed: URL?)]

    /// Undo trashes the copied files, redo puts them back; each step registers its opposite at once (so it lands on
    /// the redo stack) and awaits the work, as `FilesController.registerUndo` does.
    @MainActor static func registerImageUndo(_ files: @escaping @MainActor () async -> ImageFiles, project: Project, in um: UndoManager) {
        um.registerUndo(withTarget: project) { project in
            MainActor.assumeIsolated {
                let done = Task { @MainActor () -> ImageFiles in
                    var next: ImageFiles = []
                    for f in await files() {
                        if let t = f.trashed {
                            try? await project.restore(fromTrash: t, to: f.path)
                            next.append((f.path, nil))
                        } else {
                            next.append((f.path, try? await project.moveToTrash(f.path)))
                        }
                    }
                    return next
                }
                registerImageUndo({ await done.value }, project: project, in: um)
            }
        }
    }
}
