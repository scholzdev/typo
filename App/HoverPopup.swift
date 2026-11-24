import AppKit
import TypoKit

/// The hover card: a borderless, non-activating child panel styled like the completion popup, so the text
/// view keeps first responder and every key. Diagnostics first (severity symbol, message, hints), then the
/// tooltip; an equation's compiled image sits on top. Long content scrolls.
@MainActor final class HoverPopup {
    var isVisible: Bool { panel.isVisible }
    var frame: NSRect { panel.frame }

    private static let maxWidth: CGFloat = 640, maxHeight: CGFloat = 400, inset: CGFloat = 10
    static let equationScale: CGFloat = 2   // equations are shown larger than their size in the document
    private let panel = GlassChildPanel(cornerRadius: 14)
    private let text = NSTextView()

    init() {
        let effect = panel.content
        text.isEditable = false
        text.isSelectable = true                       // links only work in a selectable view
        text.drawsBackground = false
        text.textContainerInset = .zero
        text.textContainer?.lineFragmentPadding = 0
        text.isVerticallyResizable = true
        text.autoresizingMask = [.width]
        let scroll = NSScrollView.overlay(text)
        effect.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: Self.inset),
            scroll.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -Self.inset),
            scroll.topAnchor.constraint(equalTo: effect.topAnchor, constant: Self.inset),
            scroll.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -Self.inset),
        ])
    }

    /// Shows `info` under the first line of `info.range`, or above it near the screen bottom.
    /// `jumpHint` is a shortcut shown small at the bottom (e.g. "Follow with ⌃⌘J").
    func show(_ info: HoverInfo, jumpHint: String? = nil, in textView: NSTextView) {
        guard let window = textView.window else { return }
        let content = Self.content(info, jumpHint: jumpHint)
        text.textStorage?.setAttributedString(content)
        let bounds = content.boundingRect(with: NSSize(width: Self.maxWidth - 2 * Self.inset, height: .greatestFiniteMagnitude),
                                          options: [.usesLineFragmentOrigin, .usesFontLeading])
        let size = NSSize(width: min(ceil(bounds.width) + 2 * Self.inset + 2, Self.maxWidth),
                          height: min(ceil(bounds.height) + 2 * Self.inset, Self.maxHeight))
        text.frame = NSRect(origin: .zero, size: NSSize(width: size.width - 2 * Self.inset, height: ceil(bounds.height)))
        text.textContainer?.containerSize = NSSize(width: size.width - 2 * Self.inset, height: .greatestFiniteMagnitude)
        text.scroll(.zero)
        let first = NSRange(location: info.range.location, length: min(info.range.length, 1))
        let anchor = textView.firstRect(forCharacterRange: first, actualRange: nil)
        panel.show(size: size, x: anchor.minX, belowY: anchor.minY, aboveY: anchor.maxY, in: window,
                   appearance: textView.effectiveAppearance)   // a dark-only editor theme keeps its text readable here
    }

    func hide() { panel.hide() }

    private static func content(_ info: HoverInfo, jumpHint: String?) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let font = NSFont.systemFont(ofSize: Highlighter.fontSize - 1)   // the editor size follows the setting
        func block(_ s: NSAttributedString) {
            if out.length > 0 { out.append(NSAttributedString(string: "\n\n", attributes: [.font: NSFont.systemFont(ofSize: 4)])) }
            out.append(s)
        }
        if let e = info.equation {
            let fit = min(Self.equationScale, (Self.maxWidth - 2 * Self.inset) / e.size.width)
            let size = NSSize(width: (e.size.width * fit).rounded(), height: (e.size.height * fit).rounded())
            let image = NSImage(size: size, flipped: false) { rect in
                let shape = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
                NSGraphicsContext.saveGraphicsState()
                shape.addClip()
                NSImage(cgImage: e.image, size: size).draw(in: rect)
                NSGraphicsContext.restoreGraphicsState()
                NSColor.separatorColor.setStroke()
                shape.lineWidth = 1
                shape.stroke()
                return true
            }
            let attachment = NSTextAttachment()
            attachment.image = image
            attachment.bounds = NSRect(origin: .zero, size: size)
            block(NSAttributedString(attachment: attachment))
        }
        for d in info.diagnostics {
            let error = d.severity == .error
            let line = NSMutableAttributedString()
            let symbol = NSTextAttachment()
            let config = NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .regular)
                .applying(.init(paletteColors: [error ? .systemRed : .systemOrange]))
            symbol.image = NSImage(systemSymbolName: error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill",
                                   accessibilityDescription: error ? String(localized: "Error") : String(localized: "Warning"))?.withSymbolConfiguration(config)
            line.append(NSAttributedString(attachment: symbol))
            line.append(NSAttributedString(string: " " + d.message, attributes: [.font: font, .foregroundColor: NSColor.labelColor]))
            for h in d.hints {
                line.append(NSAttributedString(string: "\n" + String(localized: "hint: \(h)"), attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]))
            }
            block(line)
        }
        switch info.tooltip {
        case .text(let a)?, .code(let a)?: block(NSAttributedString(a))
        case nil: break
        }
        if let jumpHint {
            block(NSAttributedString(string: String(localized: "Follow with \(jumpHint)"), attributes: [
                .font: NSFont.systemFont(ofSize: max(font.pointSize - 3, 9)), .foregroundColor: NSColor.tertiaryLabelColor]))
        }
        return out
    }
}
