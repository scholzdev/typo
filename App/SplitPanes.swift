import AppKit
import SwiftUI

/// Editor and preview side by side in a real `NSSplitView`. SwiftUI's `HSplitView` re-derives the divider
/// from the children's ideal sizes whenever they change, so the split jumped with content. Here the panes
/// carry no intrinsic size, the divider is autosaved under `autosaveName`, and hiding the trailing pane
/// (pop-out) remembers the divider and puts it back.
struct SplitPanes<Leading: View, Trailing: View>: NSViewRepresentable {
    let autosaveName: String
    let showsTrailing: Bool
    let leading: Leading
    let trailing: Trailing

    private static var leadingMin: CGFloat { 320 }
    private static var trailingMin: CGFloat { 280 }

    /// Keeps the split below the window's toolbar and title area (`contentLayoutRect`). A full-size content
    /// window lets the detail column reach under it, and the editor's gutter line then ran through the title.
    final class Container: NSView {
        let split = Split()
        private var observation: NSKeyValueObservation?

        override init(frame: NSRect) {
            super.init(frame: frame)
            addSubview(split)
        }
        required init?(coder: NSCoder) { fatalError("not used") }

        override func viewDidMoveToWindow() {
            observation = window?.observe(\.contentLayoutRect) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.needsLayout = true }
            }
            needsLayout = true
        }

        override func layout() {
            super.layout()
            var frame = bounds
            if let window { frame = frame.intersection(convert(window.contentLayoutRect, from: nil)) }
            if split.frame != frame { split.frame = frame }
        }
    }

    final class Split: NSSplitView {
        var needsHalf = false
        var wantsTrailing = true
        // NSSplitView keeps drawing the divider of a hidden pane at its old position: a stray line through the editor.
        override func drawDivider(in rect: NSRect) {
            if subviews.count == 2, subviews[1].isHidden { return }
            super.drawDivider(in: rect)
        }
        override func layout() {
            // The autosave restore can un-hide a trailing pane that was open when the divider was saved.
            if subviews.count == 2, subviews[1].isHidden == wantsTrailing { subviews[1].isHidden = !wantsTrailing }
            super.layout()
            // A hidden trailing pane (pop-out, split editor off) gives its width back; NSSplitView leaves a gap.
            if subviews.count == 2, subviews[1].isHidden, subviews[0].frame != bounds { subviews[0].frame = bounds; needsDisplay = true }
            if needsHalf, bounds.width > 0 {
                needsHalf = false
                setPosition((bounds.width - dividerThickness) / 2, ofDividerAt: 0)
            }
        }
    }

    final class Coordinator: NSObject, NSSplitViewDelegate {
        var leading: NSHostingView<Leading>!
        var trailing: NSHostingView<Trailing>!
        var savedPosition: CGFloat?

        func splitView(_ s: NSSplitView, canCollapseSubview v: NSView) -> Bool { false }
        func splitView(_ s: NSSplitView, constrainMinCoordinate p: CGFloat, ofSubviewAt i: Int) -> CGFloat { max(p, SplitPanes.leadingMin) }
        func splitView(_ s: NSSplitView, constrainMaxCoordinate p: CGFloat, ofSubviewAt i: Int) -> CGFloat {
            min(p, s.bounds.width - s.dividerThickness - SplitPanes.trailingMin)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> Container {
        let c = context.coordinator
        c.leading = NSHostingView(rootView: leading)
        c.trailing = NSHostingView(rootView: trailing)
        c.leading.sizingOptions = []     // sizes come from the split view only
        c.trailing.sizingOptions = []
        let container = Container()
        let split = container.split
        split.isVertical = true
        split.dividerStyle = .thin
        split.delegate = c
        split.addSubview(c.leading)
        split.addSubview(c.trailing)
        // No stored divider yet: start at half. A stored one is applied by setting the autosave name.
        split.needsHalf = UserDefaults.standard.object(forKey: "NSSplitView Subview Frames \(autosaveName)") == nil
        split.autosaveName = autosaveName
        c.trailing.isHidden = !showsTrailing
        split.wantsTrailing = showsTrailing
        return container
    }

    func updateNSView(_ container: Container, context: Context) {
        let c = context.coordinator
        let split = container.split
        c.leading.rootView = leading
        c.trailing.rootView = trailing
        split.wantsTrailing = showsTrailing
        if !showsTrailing, !c.trailing.isHidden {
            c.savedPosition = c.leading.frame.width
            c.trailing.isHidden = true
            split.needsLayout = true
        } else if showsTrailing, c.trailing.isHidden {
            c.trailing.isHidden = false
            split.setPosition(c.savedPosition ?? (split.bounds.width - split.dividerThickness) / 2, ofDividerAt: 0)
        }
    }
}
