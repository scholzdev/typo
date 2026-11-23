import AppKit

extension NSPanel {
    /// Clear, shadowed and kept alive when closed: the whole window is the glass view.
    func styleAsGlass() {
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
    }
}

extension NSScrollView {
    /// A transparent scroll view with an auto-hiding overlay scroller, ready for Auto Layout.
    static func overlay(_ documentView: NSView) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.documentView = documentView
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return scroll
    }
}

/// A borderless, non-activating Liquid Glass panel attached as a child of the editor window, so the text view
/// keeps first responder and every key. Subviews go into `content`.
@MainActor final class GlassChildPanel {
    let content = NSView()
    private let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)

    var isVisible: Bool { panel.isVisible }
    var frame: NSRect { panel.frame }

    init(cornerRadius: CGFloat) {
        let glass = NSGlassEffectView()
        glass.cornerRadius = cornerRadius
        glass.contentView = content
        panel.contentView = glass
        panel.styleAsGlass()
    }

    /// Puts the panel at `x`, with its top `2` below `belowY`, or above `aboveY` when the screen has no room below.
    /// `preferAbove` turns that around (signature help sits above the caret line, completion below it).
    func show(size: NSSize, x: CGFloat, belowY: CGFloat, aboveY: CGFloat, in window: NSWindow, appearance: NSAppearance, preferAbove: Bool = false) {
        panel.appearance = appearance
        var origin = NSPoint(x: x, y: belowY - size.height - 2)
        let screen = (window.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        if preferAbove {
            origin.y = aboveY + 2
            if origin.y + size.height > screen.maxY { origin.y = belowY - size.height - 2 }
        } else if origin.y < screen.minY { origin.y = aboveY + 2 }
        origin.x = min(max(origin.x, screen.minX), screen.maxX - size.width)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        if panel.parent == nil { window.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil)
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }
}
