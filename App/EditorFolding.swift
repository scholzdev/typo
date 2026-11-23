import AppKit
import TypoKit

/// Folding of heading sections and multi-line bracket blocks (design/14e). The buffer keeps the folds and opens one an edit touches; the
/// FoldController hides the folded paragraphs from layout; this file keeps caret, selection, ruler and
/// decorations consistent with them.
extension EditorView.Coordinator {
    func setUpFolding(_ tv: NSTextView, decor: DecorationView) {
        tv.textContentStorage?.delegate = folds
        folds.textLayoutManager = tv.textLayoutManager
        foldAnimator.onFrame = { [weak self] s in
            guard let self, let tv = self.textView else { return }
            self.folds.setPad(s.heading, FoldPaper.height(full: s.full, eased: s.eased, folding: s.folding))
            tv.enclosingScrollView?.verticalRulerView?.needsDisplay = true
            // The heading row (badge fade) and everything below it, which moves with the placeholder.
            if let decor = self.decor {
                let visible = tv.visibleRect
                decor.setNeedsDisplay(decor.convert(NSRect(x: visible.minX, y: s.foldY - 40, width: visible.width, height: max(0, visible.maxY - s.foldY + 40)), from: tv))
            }
        }
        foldAnimator.onEnd = { [weak self] s in
            guard let self else { return }
            self.folds.held = nil
            self.folds.setPad(nil, 0)
            self.folds.relayout(s.region)
            self.textView?.enclosingScrollView?.verticalRulerView?.needsDisplay = true
            self.decor?.refresh()
        }
        folds.onChange = { [weak self] in self?.foldsChanged() }
        decor.foldedLines = { [weak self] line in
            guard let b = self?.buffer, b.isFolded(line) else { return nil }
            return b.foldRegions.first { $0.heading == line }?.lines
        }
        decor.foldTail = { [weak self] line in
            guard let b = self?.buffer, b.isFolded(line), let t = b.foldRegions.first(where: { $0.heading == line })?.tail,
                  NSMaxRange(t) <= b.storage.length else { return nil }
            return b.storage.attributedSubstring(from: t)
        }
        decor.foldFade = { [weak self] in self?.foldAnimator.progress($0).map { $0.state.folding ? $0.eased : 1 } }
        decor.shownLine = { [weak self] in self?.buffer?.visibleLine(of: $0) ?? $0 }
        decor.onBadgeClick = { [weak self] in self?.setFolded([$0], false) }
        decor.bookmarkStarts = { [weak self] in self?.bookmarkStarts ?? [] }
        NotificationCenter.default.addObserver(forName: .bookmarksChanged, object: nil, queue: .main) { [weak decor] _ in
            MainActor.assumeIsolated { decor?.needsDisplay = true }
        }
    }

    /// Nil: no fold starts on the line at `start`; else whether it is folded.
    func foldMark(at start: Int) -> Bool? {
        guard display.folding, let b = buffer, b.foldRegions.contains(where: { $0.heading == start }) else { return nil }
        return b.isFolded(start)
    }

    func setFolded(_ headings: [Int], _ folded: Bool) {
        guard let buffer else { return }
        foldAnimator.finish()
        func instant() {
            if folded { buffer.fold(headings) } else { buffer.unfold(headings) }
            folds.update()
        }
        // Animate a single region only (not fold all), and not under Reduce Motion.
        guard headings.count == 1, let h = headings.first, display.folding, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let tv = textView, tv.window != nil, buffer.isFolded(h) != folded,
              let r = buffer.foldRegions.first(where: { $0.heading == h }) else { return instant() }
        let region = NSRange(location: h, length: r.end - h)
        if folded {
            // The lines are laid out now: picture them, then hide them behind a placeholder of their height.
            guard let paper = foldPaper(h, tv), folds.setPad(h, paper.full) else { folds.setPad(nil, 0); return instant() }
            buffer.fold([h])
            folds.update(region)
            startFold(h, folding: true, paper, region: region, tv)
        } else {
            // Shown for one layout to picture them, then held hidden until the placeholder has grown to their height.
            buffer.unfold([h])
            folds.update(region)
            guard let paper = foldPaper(h, tv) else { return }
            folds.held = r.hidden
            folds.relayout(region)
            guard folds.setPad(h, 0) else { folds.held = nil; folds.relayout(region); return }
            startFold(h, folding: false, paper, region: region, tv)
        }
    }

    private func startFold(_ h: Int, folding: Bool, _ paper: (full: CGFloat, foldY: CGFloat, views: [(FoldPaperView, NSView)]), region: NSRange, _ tv: NSTextView) {
        paper.views.forEach { $1.addSubview($0, positioned: .above, relativeTo: nil) }
        foldAnimator.start(.init(heading: h, folding: folding, start: CACurrentMediaTime(), full: paper.full, foldY: paper.foldY, region: region),
                           papers: paper.views.map(\.0), on: tv)
    }

    /// Paper-fold views of the open region's lines under `heading`, as far as they are visible, in the text and in the
    /// gutter; nil when the fold line is not on screen or nothing is under it.
    private func foldPaper(_ heading: Int, _ tv: NSTextView) -> (full: CGFloat, foldY: CGFloat, views: [(FoldPaperView, NSView)])? {
        let visible = tv.visibleRect
        guard let block = foldBlock(heading), block.foldY >= visible.minY, block.foldY < visible.maxY else { return nil }
        let full = min(block.hidden, visible.maxY - block.foldY)
        var background = CGColor.black
        tv.effectiveAppearance.performAsCurrentDrawingAppearance { background = Highlighter.style.colors.background.cgColor }
        var views: [(FoldPaperView, NSView)] = []
        func add(_ host: NSView, _ rect: NSRect) {
            guard let s = FoldAnimator.snapshot(host, rect) else { return }
            views.append((FoldPaperView(image: s.image, scale: s.scale, frame: rect, full: full, background: background), host))
        }
        add(tv, NSRect(x: visible.minX, y: block.foldY, width: visible.width, height: full))
        guard !views.isEmpty else { return nil }
        // Only a flipped ruler shares the text view's y direction; otherwise the gutter just reflows.
        if let ruler = tv.enclosingScrollView?.verticalRulerView, ruler.isFlipped {
            add(ruler, NSRect(x: 0, y: ruler.convert(NSPoint(x: 0, y: block.foldY), from: tv).y, width: ruler.bounds.width, height: full))
        }
        return (full, block.foldY, views)
    }

    /// The bottom of the heading row in text view coordinates, open or folded; nil when the heading is hidden itself.
    /// Without a placeholder: read it before a fold animates.
    func foldLineY(_ heading: Int) -> CGFloat? {
        guard let tv = textView, let tlm = tv.textLayoutManager, let tcs = tv.textContentStorage, let b = buffer, b.hidden(at: heading) == nil,
              let loc = tcs.location(tcs.documentRange.location, offsetBy: b.visibleLine(of: heading)),
              let frag = tlm.textLayoutFragment(for: loc) else { return nil }
        return frag.layoutFragmentFrame.maxY + tv.textContainerOrigin.y
    }

    /// The fold line (bottom of the heading row) and the height of the hidden lines under it, in text view coordinates;
    /// only while the region is open, and nil when its heading is not on screen.
    private func foldBlock(_ heading: Int) -> (foldY: CGFloat, hidden: CGFloat)? {
        guard let tv = textView, let tlm = tv.textLayoutManager, let tcs = tv.textContentStorage, let b = buffer, b.hidden(at: heading) == nil,
              let r = b.foldRegions.first(where: { $0.heading == heading }) else { return nil }
        func frame(_ offset: Int) -> CGRect? {
            tcs.location(tcs.documentRange.location, offsetBy: b.visibleLine(of: offset)).flatMap { tlm.textLayoutFragment(for: $0)?.layoutFragmentFrame }
        }
        guard let head = frame(r.heading), let last = frame(r.end - 1) else { return nil }
        return (head.maxY + tv.textContainerOrigin.y, last.maxY - head.maxY)
    }

    func toggleFold(at heading: Int) { setFolded([heading], !(buffer?.isFolded(heading) ?? true)) }

    func foldAtCaret() {
        guard display.folding, let tv = textView, let r = buffer?.foldRegion(at: tv.selectedRange().location, folded: false) else { return NSSound.beep() }
        setFolded([r.heading], true)
    }

    func unfoldAtCaret() {
        guard let tv = textView, let r = buffer?.foldRegion(at: tv.selectedRange().location, folded: true) else { return NSSound.beep() }
        setFolded([r.heading], false)
    }

    /// Without the folding ribbon nothing folds: a hidden section would have no triangle to open it.
    func foldAll() {
        guard display.folding else { return NSSound.beep() }
        foldAnimator.finish(); buffer?.foldAll(); folds.update()
    }
    func unfoldAll() { foldAnimator.finish(); buffer?.unfoldAll(); folds.update() }

    /// Opens the folds a programmatic selection of `r` would land in.
    func revealFolds(_ r: NSRange) { _ = folds.selection(r, from: r, keyboard: false) }

    /// The keyboard steps over a fold; find, jumps and anything else that selects hidden text opens it. A file switch
    /// is left alone: the old file's caret means nothing in the new one.
    @objc func textView(_ textView: NSTextView, willChangeSelectionFromCharacterRange old: NSRange, toCharacterRange new: NSRange) -> NSRange {
        if swapping { return new }
        if !programmatic { foldAnimator.finish() }   // the user moving the caret ends a fold's motion
        return folds.selection(new, from: old, keyboard: !programmatic && NSApp.currentEvent?.type == .keyDown)
    }

    /// After a new layout: a caret or selection end that a fold now hides moves to the end of the heading line.
    private func foldsChanged() {
        guard let tv = textView, let buffer else { return }
        let sel = tv.selectedRange()
        if let h = buffer.hidden(at: sel.location) ?? (sel.length > 0 ? buffer.hidden(at: NSMaxRange(sel)) : nil) {
            let caret = NSRange(location: max(h.range.location - 1, 0), length: 0)
            selectProgrammatically(caret, in: tv, scroll: false)
        }
        tv.textLayoutManager?.textViewportLayoutController.layoutViewport()
        tv.needsDisplay = true
        tv.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        decor?.refresh()
    }
}

extension LineNumberRuler {
    /// A disclosure chevron in the ribbon right of the number, as in Xcode, on a line that starts a fold: pointing right when folded.
    func drawFoldMark(at start: Int, y: CGFloat, height: CGFloat) {
        guard let folded = editor?.foldMark(at: start), folded || hovered || editor?.foldAnimator.progress(start) != nil else { return }
        if folded || editor?.foldAnimator.progress(start) != nil { drawFoldNotch(y: y, height: height) }
        let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold).applying(.init(paletteColors: [Highlighter.style.colors.ruler]))
        if let a = editor?.foldAnimator.progress(start),
           let img = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            // One right-pointing symbol turned 0...90 degrees (clockwise in this flipped view): right when folded, down when open.
            let degrees = 90 * (a.state.folding ? 1 - a.eased : a.eased)
            let center = NSPoint(x: ruleThickness - 12 + img.size.width / 2, y: y + max(height, img.size.height) / 2)
            NSGraphicsContext.saveGraphicsState()
            let t = NSAffineTransform()
            t.translateX(by: center.x, yBy: center.y); t.rotate(byDegrees: degrees); t.translateX(by: -center.x, yBy: -center.y)
            t.concat()
            img.draw(in: NSRect(x: center.x - img.size.width / 2, y: center.y - img.size.height / 2, width: img.size.width, height: img.size.height))
            NSGraphicsContext.restoreGraphicsState()
            return
        }
        // Folded, the chevron sits white on the solid bar, as in Xcode.
        let tint = folded ? NSImage.SymbolConfiguration(pointSize: 9, weight: .bold).applying(.init(paletteColors: [.white])) : config
        guard let img = NSImage(systemSymbolName: folded ? "chevron.right" : "chevron.down", accessibilityDescription: nil)?.withSymbolConfiguration(tint) else { return }
        img.draw(in: NSRect(x: ruleThickness - 12, y: y + max(height, img.size.height) / 2 - img.size.height / 2, width: img.size.width, height: img.size.height))
    }

    /// Xcode's folded line: a solid grey bar in the ribbon column across the fold line's row, under the white chevron.
    private func drawFoldNotch(y: CGFloat, height: CGFloat) {
        let w: CGFloat = 12, h = max(height, 1), x = ruleThickness - 14
        Highlighter.style.colors.text.withAlphaComponent(0.45).setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: 2, yRadius: 2).fill()
    }

    /// Xcode's ribbon: while the pointer is over the gutter, a rounded track with every fold region as a capsule, nested
    /// ones darker, the one under the pointer darkest. Drawn from `drawHashMarksAndLabels` before the chevrons.
    func drawFoldRibbon(_ tv: NSTextView, _ tlm: NSTextLayoutManager, _ tcs: NSTextContentStorage, viewport: NSTextRange) {
        guard hovered, let editor, editor.display.folding, let b = editor.buffer else { editor?.decor?.hoverBand = nil; return }
        let regions = b.foldRegions
        let vs = tcs.offset(of: viewport.location), ve = tcs.offset(of: viewport.endLocation)
        let origin = tv.textContainerOrigin
        let color = Highlighter.style.colors.text
        let x = ruleThickness - 13, w: CGFloat = 10
        func fill(_ minY: CGFloat, _ maxY: CGFloat, alpha: CGFloat) {
            color.withAlphaComponent(alpha).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: minY, width: w, height: maxY - minY), xRadius: w / 2, yRadius: w / 2).fill()
        }
        /// The row (top, bottom) in the ruler of the line `offset` shows on.
        func row(_ offset: Int) -> (CGFloat, CGFloat)? { rowSpan(of: offset) }
        fill(bounds.minY, bounds.maxY, alpha: 0.06)
        var under: FoldRegion?
        defer { editor.decor?.hoverBand = under.map { NSRange(location: $0.heading, length: $0.end - $0.heading) } }   // the text area's faint band
        if let hoverY {
            let p = tv.convert(convert(NSPoint(x: 0, y: hoverY), to: nil), from: nil)
            if let frag = tlm.textLayoutFragment(for: CGPoint(x: 0, y: p.y - origin.y)) {
                under = Folding.innermost(regions, at: tcs.offset(of: frag.rangeInElement.location))
            }
        }
        // Lines an unfold still holds hidden have no layout yet: their own capsules wait for it.
        for c in Folding.capsules(regions, in: vs..<ve) where b.hidden(at: c.region.heading) == nil
            && !(editor.folds.held.map { NSLocationInRange(c.region.heading, $0) } ?? false) {
            var last = b.isFolded(c.region.heading) ? c.region.heading : c.region.end - 1
            // An outer region ending inside the held lines ends on the unfolding heading's row, which carries the growing placeholder.
            if let h = editor.folds.held, NSLocationInRange(last, h) { last = h.location - 1 }
            guard last >= vs, c.region.heading < ve else { continue }
            // While a fold animates the heading row carries the placeholder, so the capsule shrinks and grows with it.
            let animating = c.region.heading >= vs && editor.foldAnimator.progress(c.region.heading) != nil
            guard let top = c.region.heading >= vs ? row(c.region.heading)?.0 : bounds.minY - w,
                  let bottom = animating ? row(c.region.heading)?.1 : last < ve ? row(last)?.1 : bounds.maxY + w else { continue }
            fill(top, bottom, alpha: c.region == under ? 0.35 : 0.06 + 0.07 * CGFloat(c.depth + 1))
        }
    }

    /// The row (top, bottom) in the ruler of the line `offset` shows on.
    func rowSpan(of offset: Int) -> (CGFloat, CGFloat)? {
        guard let tv = textView, let tlm = tv.textLayoutManager, let tcs = tv.textContentStorage, let b = editor?.buffer,
              let loc = tcs.location(tcs.documentRange.location, offsetBy: b.visibleLine(of: offset)), let f = tlm.textLayoutFragment(for: loc) else { return nil }
        let top = convert(NSPoint(x: 0, y: f.layoutFragmentFrame.minY + tv.textContainerOrigin.y), from: tv).y
        return (top, top + f.layoutFragmentFrame.height)
    }

    /// A click on a row that starts a fold folds or unfolds it.
    override func mouseDown(with event: NSEvent) {
        if clickRainbow(event) { return }                          // an assistant change bar
        if editor?.gitGutter.click(event) == true { return }      // a git change bar at the left edge
        guard let tv = textView, let tlm = tv.textLayoutManager, let tcs = tv.textContentStorage else { return super.mouseDown(with: event) }
        let p = tv.convert(event.locationInWindow, from: nil)
        guard let frag = tlm.textLayoutFragment(for: CGPoint(x: 0, y: p.y - tv.textContainerOrigin.y)) else { return super.mouseDown(with: event) }
        let start = tcs.offset(of: frag.rangeInElement.location)
        guard editor?.foldMark(at: start) != nil else {
            // Left of the fold ribbon, a click bookmarks the line (heading rows keep folding on any click).
            if convert(event.locationInWindow, from: nil).x < ruleThickness - 13 { editor?.toggleBookmark(at: start) } else { super.mouseDown(with: event) }
            return
        }
        editor?.toggleFold(at: start)
    }
}

extension DecorationView {
    /// "⋯ N lines" after a folded heading's text; returns where it ends, nil on other lines.
    func drawFoldBadge(_ frag: NSTextLayoutFragment, at start: Int, frame: NSRect) -> CGFloat? {
        guard let n = foldedLines?(start), let last = frag.textLineFragments.last else { return nil }
        let colors = Highlighter.style.colors
        let fade = foldFade?(start) ?? 1
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: Highlighter.fontSize - 2, weight: .medium),
                                                    .foregroundColor: colors.ruler.withAlphaComponent(fade)]
        // A block reads `{ ··· }` like Xcode: a dots pill, then the closing line in its own colours; a section gives its line count.
        let tail = foldTail?(start)
        let label = (tail != nil ? "•••" : "⋯ \(n) \(n == 1 ? "line" : "lines")") as NSString
        let size = label.size(withAttributes: attrs)
        let b = last.typographicBounds
        let rect = NSRect(x: frame.minX + b.maxX + (tail != nil ? 5 : 8), y: frame.minY + b.minY + (b.height - size.height - 2) / 2,
                          width: ceil(size.width) + 12, height: ceil(size.height) + 2)
        colors.ruler.withAlphaComponent(0.15 * fade).setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
        label.draw(at: NSPoint(x: rect.minX + 6, y: rect.minY + 1), withAttributes: attrs)
        badgeHits.append((rect, start))
        guard let tail, tail.length > 0 else { return rect.maxX }
        let at = NSPoint(x: rect.maxX + 5, y: frame.minY + b.minY + (b.height - tail.size().height) / 2)
        tail.draw(at: at)
        return at.x + tail.size().width
    }
}
