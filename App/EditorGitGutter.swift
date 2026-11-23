import AppKit
import SwiftUI
import TypoKit

extension Notification.Name {
    /// Posted by `GitModel` after each refresh (saves, commits, branch switches, app activation); the object is the Project.
    static let gitDidRefresh = Notification.Name("Tympan.gitDidRefresh")
    /// Asks the window's `GitModel` to refresh after git changed outside it (the gutter staged a hunk).
    static let gitNeedsRefresh = Notification.Name("Tympan.gitNeedsRefresh")
}

/// Git in the gutter (roadmap 6.1, 6.5): change bars against HEAD, a blame card when the pointer rests on a line,
/// and a popover on a bar with Revert (or, inside a merge conflict, Keep Mine / Theirs / Both). HEAD's text is
/// loaded once per file and after each git refresh; edits are diffed against it in memory, so unsaved changes show.
@MainActor final class GitGutter: NSObject {
    weak var ruler: LineNumberRuler? {
        didSet {
            guard ruler !== oldValue, let ruler else { return }
            ruler.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                                 owner: self, userInfo: nil))
            if let clip = ruler.scrollView?.contentView {
                NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: clip)
            }
        }
    }
    private(set) var marks = GitGutterMarks()
    private weak var project: Project?
    private weak var buffer: Buffer?
    private var base: String?
    private var loading: Task<Void, Never>?
    /// Settings › Source Control's "Show source control changes" and "Include upstream changes" as last loaded.
    private var applied: (shows: Bool, upstream: Bool)?
    private var diffing: Task<Void, Never>?

    // Blame: loaded for the text as it is when first asked, again after edits.
    private var blame: [GitBlameLine] = []
    private var edits = 0
    private var blameEdits: Int?
    private var dwell: Task<Void, Never>?
    private var hoverLine: Int?
    private let card = GlassChildPanel(cornerRadius: 10)
    private let cardLabel = NSTextField(wrappingLabelWithString: "")
    private var popover: NSPopover?
    private var popoverLine = 0

    /// Width the gutter reserves for the bars when it shows no numbers.
    static let barZone: CGFloat = 8
    /// The change bar is 5 pt wide at the gutter's left edge, like the assistant's bars; a click within `barWidth + 2` opens its popover.
    static let barWidth: CGFloat = 5

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(gitRefreshed), name: .gitDidRefresh, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(defaultsChanged), name: UserDefaults.didChangeNotification, object: nil)
        cardLabel.translatesAutoresizingMaskIntoConstraints = false
        cardLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        cardLabel.preferredMaxLayoutWidth = 340
        card.content.addSubview(cardLabel)
        NSLayoutConstraint.activate([
            cardLabel.leadingAnchor.constraint(equalTo: card.content.leadingAnchor, constant: 10),
            cardLabel.trailingAnchor.constraint(equalTo: card.content.trailingAnchor, constant: -10),
            cardLabel.topAnchor.constraint(equalTo: card.content.topAnchor, constant: 7),
            cardLabel.bottomAnchor.constraint(equalTo: card.content.bottomAnchor, constant: -7),
        ])
    }

    /// From `updateNSView`: a new file drops the old marks and loads its HEAD text.
    func show(_ buffer: Buffer, in project: Project) {
        guard buffer !== self.buffer else { return }
        let nc = NotificationCenter.default
        if let old = self.buffer {
            nc.removeObserver(self, name: NSTextStorage.didProcessEditingNotification, object: old.storage)
            nc.removeObserver(self, name: .bufferAIMarksChanged, object: old)
            nc.removeObserver(self, name: .bufferInlineDiffChanged, object: old)
        }
        nc.addObserver(self, selector: #selector(aiMarksChanged), name: .bufferAIMarksChanged, object: buffer)
        nc.addObserver(self, selector: #selector(aiMarksChanged), name: .bufferInlineDiffChanged, object: buffer)
        nc.addObserver(self, selector: #selector(edited), name: NSTextStorage.didProcessEditingNotification, object: buffer.storage)
        self.buffer = buffer
        self.project = project
        base = nil
        blame = []
        blameEdits = nil
        diffing?.cancel()
        hideCard()
        set(GitGutterMarks())
        reload()
    }

    /// The ribbon of assistant changes follows the buffer's marks and its pending inline diff.
    @objc private func aiMarksChanged() { ruler?.needsDisplay = true }

    @objc private func gitRefreshed(_ n: Notification) {
        guard let p = n.object as? Project, p === project else { return }
        blameEdits = nil                                // a commit changes who "last changed" a line
        reload()
    }

    /// Reloads only when one of the gutter's settings changed; the notification comes for every default written.
    @objc private func defaultsChanged(_ n: Notification) {
        guard let applied, applied.shows != SourceControl.showsChanges || applied.upstream != SourceControl.includesUpstream else { return }
        reload()
    }

    /// Any text change, typed or applied by the app; highlighting (attributes only) is skipped.
    @objc private func edited(_ n: Notification) {
        guard (n.object as? NSTextStorage)?.editedMask.contains(.editedCharacters) == true else { return }
        edits += 1
        hideCard()
        recompute(after: .milliseconds(250))
    }

    /// The base the edits are diffed against: HEAD, or the upstream branch when the settings include upstream changes
    /// (HEAD again without an upstream). With changes hidden there is no base, so no bars, popover or blame.
    private func reload() {
        guard let project, let buffer else { return }
        let path = buffer.path
        let shows = SourceControl.showsChanges, upstream = SourceControl.includesUpstream
        applied = (shows, upstream)
        loading?.cancel()
        guard shows else {
            base = nil
            diffing?.cancel()
            hideCard()
            return set(GitGutterMarks())
        }
        loading = Task { [weak self] in
            var text: String?
            if upstream { text = await project.upstreamText(of: path) }
            if text == nil { text = await project.headText(of: path) }
            guard let self, !Task.isCancelled, self.buffer === buffer else { return }
            self.base = text
            self.recompute(after: nil)
        }
    }

    /// Debounced while typing; the text is read after the wait and diffed off the main actor.
    private func recompute(after delay: Duration?) {
        diffing?.cancel()
        guard let base, let buffer else { return set(GitGutterMarks()) }
        diffing = Task { [weak self] in
            if let delay { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            let current = buffer.storage.string
            let m = await Task.detached(priority: .utility) { GitGutterMarks.compute(base: base, current: current) }.value
            guard let self, !Task.isCancelled, self.buffer === buffer else { return }
            self.set(m)
        }
    }

    private func set(_ m: GitGutterMarks) {
        guard m != marks else { return }
        marks = m
        ruler?.needsDisplay = true
    }

    // MARK: Lines under the pointer

    /// The 1-based source line at a point in the ruler, and that line's rect in the ruler.
    private func line(at point: NSPoint) -> (line: Int, rect: NSRect)? {
        guard let ruler, let tv = ruler.textView, let tlm = tv.textLayoutManager, let tcs = tv.textContentStorage else { return nil }
        let p = tv.convert(ruler.convert(point, to: nil), from: nil)
        guard let frag = tlm.textLayoutFragment(for: CGPoint(x: 0, y: p.y - tv.textContainerOrigin.y)) else { return nil }
        let start = tcs.offset(of: frag.rangeInElement.location)
        let text = tv.string.utf16
        let line = 1 + text.prefix(start).reduce(0) { $1 == 10 ? $0 + 1 : $0 }
        let frame = frag.layoutFragmentFrame.offsetBy(dx: 0, dy: tv.textContainerOrigin.y)
        let top = ruler.convert(NSPoint(x: 0, y: frame.minY), from: tv).y
        return (line, NSRect(x: 0, y: top, width: ruler.ruleThickness, height: frame.height))
    }

    // MARK: Blame card

    @objc(mouseMoved:) func mouseMoved(with event: NSEvent) {
        guard let ruler else { return }
        ruler.hoverWindow = event.locationInWindow
        ruler.hoverY = ruler.convert(event.locationInWindow, from: nil).y
        guard let hit = line(at: ruler.convert(event.locationInWindow, from: nil)) else { return hideCard() }
        guard hit.line != hoverLine else { return }
        hoverLine = hit.line
        card.hide()
        dwell?.cancel()
        guard project?.isRepository == true, base != nil else { return }
        dwell = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, let self else { return }
            await self.showBlame(line: hit.line, rect: hit.rect)
        }
    }

    @objc(mouseExited:) func mouseExited(with event: NSEvent) { hideCard(); ruler?.hovered = false; ruler?.hoverWindow = nil; ruler?.hoverY = nil }
    @objc private func scrolled() { if card.isVisible || dwell != nil { hideCard() } }
    @objc(mouseEntered:) func mouseEntered(with event: NSEvent) { ruler?.hovered = true }

    func hideCard() {
        dwell?.cancel()
        hoverLine = nil
        card.hide()
    }

    private func showBlame(line: Int, rect: NSRect) async {
        guard let project, let buffer, let ruler, let window = ruler.window else { return }
        if blameEdits != edits {
            let at = edits
            let result = await project.blame(of: buffer.path, text: buffer.storage.string)
            guard self.buffer === buffer, edits == at, !Task.isCancelled else { return }
            blame = result
            blameEdits = at
        }
        guard hoverLine == line, blame.indices.contains(line - 1) else { return }
        let b = blame[line - 1]
        cardLabel.stringValue = b.isCommitted
            ? "\(b.author) · \(b.date.formatted(.relative(presentation: .named)))\n\(b.summary)\n\(b.shortHash) · \(b.date.formatted(date: .abbreviated, time: .shortened))"
            : "Not committed yet"
        let size = cardLabel.fittingSize
        let screen = window.convertToScreen(ruler.convert(rect, to: nil))
        card.show(size: NSSize(width: size.width + 20, height: size.height + 14), x: screen.maxX + 4, belowY: screen.minY, aboveY: screen.maxY,
                  in: window, appearance: ruler.effectiveAppearance)
    }

    // MARK: Clicks on a bar

    /// A click in the bar zone on a changed line opens its popover; false lets the ruler handle the click (folding).
    func click(_ event: NSEvent) -> Bool {
        guard let ruler, let buffer, let base else { return false }
        let p = ruler.convert(event.locationInWindow, from: nil)
        guard p.x < Self.barWidth + 2, let hit = line(at: p) else { return false }
        hideCard()
        let text = buffer.storage.string
        // Computed afresh: the drawn marks can be a keystroke behind.
        if let conflict = ConflictRegion.parse(text).first(where: { $0.contains(line: hit.line) }) {
            present(.conflict(conflict), at: hit.rect)
            return true
        }
        guard let hunk = GitGutterMarks.compute(base: base, current: text).hunk(at: hit.line) else { return false }
        popoverLine = hit.line
        present(.hunk(hunk), at: hit.rect)
        return true
    }

    private func present(_ subject: GutterPopover.Subject, at rect: NSRect) {
        guard let ruler, let buffer else { return }
        popover?.close()
        let pop = NSPopover()
        pop.behavior = .transient
        pop.contentViewController = NSHostingController(rootView: GutterPopover(subject: subject) { [weak self, weak buffer, weak pop] action in
            pop?.close()
            guard let self, let buffer else { return }
            self.perform(action, subject, in: buffer)
        })
        pop.show(relativeTo: rect, of: ruler, preferredEdge: .maxX)
        popover = pop
    }

    /// Edits go through the buffer, so Undo takes them back like typing.
    private func perform(_ action: GutterPopover.Action, _ subject: GutterPopover.Subject, in buffer: Buffer) {
        let text = buffer.storage.string
        switch (action, subject) {
        case (.revert, .hunk(let h)):
            // The text may have changed since the popover opened: find the hunk again where it now is.
            guard let base, let now = GitGutterMarks.compute(base: base, current: text).hunks.first(where: { $0.oldLines == h.oldLines && $0.newLines == h.newLines }) else { return }
            buffer.apply([now.revert(in: text)], actionName: "Revert Change")
        case (.stage, .hunk):
            guard let project else { return }
            let path = buffer.path, line = popoverLine
            Task {
                do { try await project.stageHunk(of: path, text: text, line: line) } catch { showAlert("Couldn’t Stage the Change", error.localizedDescription) }
                NotificationCenter.default.post(name: .gitNeedsRefresh, object: project)
            }
        case (.keep(let choice), .conflict(let c)):
            guard let now = ConflictRegion.parse(text).first(where: { $0.mine == c.mine && $0.theirs == c.theirs }) else { return }
            buffer.apply([now.resolution(choice, in: text)], actionName: "Resolve Conflict")
        default: break
        }
    }
}

/// The popover on a gutter bar: what HEAD had and what is there now, or the two sides of a conflict.
struct GutterPopover: View {
    enum Subject { case hunk(GitGutterMarks.Hunk), conflict(ConflictRegion) }
    enum Action { case revert, stage, keep(ConflictRegion.Choice) }

    let subject: Subject
    let act: (Action) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch subject {
            case .hunk(let h):
                Text(h.isDeletion ? "Deleted Lines" : h.oldLines.isEmpty ? "Added Lines" : "Changed Lines").font(.headline)
                lines(h.oldLines, sign: "\u{2212}", color: .red)
                lines(h.newLines, sign: "+", color: .green)
                HStack {
                    Spacer()
                    Button("Stage") { act(.stage) }.buttonStyle(.glass).help("Stage just this change for the next commit, as it is in the editor now")
                    Button("Revert") { act(.revert) }.buttonStyle(.glass).help("Put back what the last commit has here (Undo takes it back)")
                }
            case .conflict(let c):
                Text("Merge Conflict").font(.headline)
                Text(c.mineLabel.isEmpty ? "Mine" : "Mine (\(c.mineLabel))").font(.caption).foregroundStyle(.secondary)
                lines(c.mine, sign: "", color: .blue)
                Text(c.theirsLabel.isEmpty ? "Theirs" : "Theirs (\(c.theirsLabel))").font(.caption).foregroundStyle(.secondary)
                lines(c.theirs, sign: "", color: .purple)
                HStack {
                    Spacer()
                    Button("Keep Mine") { act(.keep(.mine)) }.buttonStyle(.glass)
                    Button("Keep Theirs") { act(.keep(.theirs)) }.buttonStyle(.glass)
                    Button("Keep Both") { act(.keep(.both)) }.buttonStyle(.glass)
                }
            }
        }
        .padding(12)
        .frame(minWidth: 280, maxWidth: 520)
    }

    @ViewBuilder private func lines(_ ls: [String], sign: String, color: Color) -> some View {
        if !ls.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(ls.prefix(200).enumerated()), id: \.offset) { _, l in
                        Text(sign.isEmpty ? (l.isEmpty ? " " : l) : "\(sign) \(l)").lineLimit(1).truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .font(.system(size: 11, design: .monospaced))
                .padding(6)
            }
            .frame(maxHeight: 160)
            .fixedSize(horizontal: false, vertical: true)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

extension LineNumberRuler {
    /// A blue pill at the gutter's left edge over each run of changed lines, a blue wedge where lines were deleted.
    /// Lines the assistant changed get its rainbow bar instead (`layoutRainbow`).
    func drawGitMark(line: Int, start: Int, end: Int, y: CGFloat, height: CGFloat) {
        guard let marks = editor?.gitGutter.marks, !marks.isEmpty else { return }
        if editor?.buffer?.marksAssistantChange(start, end) == true { return }
        let x: CGFloat = 1, w = GitGutter.barWidth
        NSColor.systemBlue.setFill()
        if marks.lines[line] != nil {
            // Rounded only where the run starts and ends: the pill runs on behind the neighbouring changed lines.
            let above = marks.lines[line - 1] != nil, below = marks.lines[line + 1] != nil
            let pill = NSRect(x: x, y: y - (above ? w : 0), width: w, height: height + (above ? w : 0) + (below ? w : 0))
            NSGraphicsContext.saveGraphicsState()
            NSRect(x: x, y: y, width: w, height: height).clip()
            NSBezierPath(roundedRect: pill, xRadius: w / 2, yRadius: w / 2).fill()
            NSGraphicsContext.restoreGraphicsState()
        } else if editor?.foldMark(at: start) == true, let hidden = editor?.buffer?.foldRegions.first(where: { $0.heading == start })?.lines {
            // A folded heading stands for its hidden lines: a dashed bar when any of them changed.
            let range = (line + 1)...(line + max(hidden, 1))
            if range.contains(where: { marks.lines[$0] != nil || marks.deletedAfter.contains($0) }) {
                var dy: CGFloat = 0
                while dy < height { NSRect(x: x, y: y + dy, width: w, height: min(2, height - dy)).fill(); dy += 4 }
            }
        }
        var edges: [CGFloat] = []
        if marks.deletedAfter.contains(line) { edges.append(y + height) }
        if line == 1, marks.deletedAfter.contains(0) { edges.append(y) }
        for edge in edges {
            let s: CGFloat = 4
            let wedge = NSBezierPath()
            wedge.move(to: NSPoint(x: s + 1, y: edge))
            wedge.line(to: NSPoint(x: 0, y: edge - s))
            wedge.line(to: NSPoint(x: 0, y: edge + s))
            wedge.close()
            wedge.fill()
        }
    }
}
