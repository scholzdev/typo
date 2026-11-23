import AppKit
import SwiftUI
import TypoKit

/// A key-capable borderless panel that hands Esc to `onEscape`.
private final class DocsKeyPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53 { onEscape?(); return }
        super.sendEvent(event)
    }
}

/// One block of a docs Markdown string.
private enum DocsBlock: Identifiable {
    case prose(Int, AttributedString)
    case code(Int, AttributedString)

    var id: Int {
        switch self { case .prose(let i, _), .code(let i, _): i }
    }

    /// Fenced code blocks become code; everything else is prose with `#` headings turned bold (HoverText is inline only).
    @MainActor static func parse(_ markdown: String) -> [DocsBlock] {
        var out: [DocsBlock] = []
        var prose: [String] = [], code: [String] = [], lang = "", inCode = false
        func flushProse() {
            let text = prose.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            prose = []
            if !text.isEmpty { out.append(.prose(out.count, HoverText.markdown(text))) }
        }
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("```") {
                if inCode {
                    let body = code.joined(separator: "\n")
                    let typst = lang.hasPrefix("typ") || lang == "example"
                    var a = typst ? HoverText.code(body) : AttributedString(body)
                    if !typst { a.font = .system(.callout, design: .monospaced) }
                    out.append(.code(out.count, a))
                    code = []
                } else {
                    flushProse()
                    lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
                inCode.toggle()
            } else if inCode {
                code.append(line)
            } else if line.hasPrefix("#"), let space = line.firstIndex(of: " ") {
                prose.append("**\(line[line.index(after: space)...])**")
            } else {
                prose.append(line)
            }
        }
        if inCode { out.append(.code(out.count, AttributedString(code.joined(separator: "\n")))) }
        flushProse()
        return out
    }
}

/// Colors a signature from `Project.signature` like Typst's documentation: the name as a function, parameter types
/// purple, `none` and `auto` red, string values green.
@MainActor enum SignatureText {
    static func attributed(_ signature: String) -> AttributedString {
        let font = Font.system(size: Highlighter.fontSize - 1, design: .monospaced)
        var out = AttributedString()
        func add(_ s: some StringProtocol, _ color: Color = .primary) {
            var a = AttributedString(String(s))
            a.font = font
            a.foregroundColor = color
            out += a
        }
        for (n, line) in signature.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if n > 0 { add("\n") }
            if n == 0, let open = line.firstIndex(of: "(") {
                add(line[..<open], .blue)
                add(line[open...], .secondary)
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { add(line, line.trimmingCharacters(in: .whitespaces) == ")" ? .secondary : .primary); continue }
            add(line[..<colon])
            add(": ", .secondary)
            var types = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            let comma = types.hasSuffix(",")
            if comma { types.removeLast() }
            for (i, t) in types.components(separatedBy: " | ").enumerated() {
                if i > 0 { add(" | ", .secondary) }
                add(t, t == "none" || t == "auto" ? .red : t.hasPrefix("\"") ? .green : .purple)
            }
            if comma { add(",", .secondary) }
        }
        return out
    }
}

private struct DocsView: View {
    let doc: BuiltinDoc
    /// The function with every parameter and its types (Quick Help), on top.
    let signature: AttributedString?
    /// The hover tooltip (signature and one-line summary), shown on top exactly as when hovering.
    let tip: AttributedString?
    let blocks: [DocsBlock]
    let scrolls: Bool
    let open: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Everything but the link scrolls: a long signature (`text` has 40 parameters) must not be cut off.
            if scrolls { ScrollView { scrolled } } else { scrolled }
            if let url = doc.url {
                Button("Open in Typst Documentation", systemImage: "safari") { open(url) }
                    .buttonStyle(.glass).controlSize(.regular)
                    .padding(.horizontal, 18).padding(.vertical, 12)
            }
        }
        // Only the shown panel fills its window; the measuring copy must report its own size.
        .frame(maxWidth: scrolls ? .infinity : nil, maxHeight: scrolls ? .infinity : nil, alignment: .topLeading)
    }

    private var scrolled: some View {
        VStack(alignment: .leading, spacing: 0) {
            if signature != nil || tip != nil {
                VStack(alignment: .leading, spacing: 10) {
                    if let signature { Text(signature).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                    if signature != nil, tip != nil { Divider() }
                    if let tip { Text(tip).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                }
                .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 10)
                if !blocks.isEmpty { Divider().padding(.horizontal, 18).padding(.bottom, 10) }
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(doc.name).font(.system(.title3, design: .monospaced).bold())
                    Text("Typst built-in").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 8)
            }
            if !blocks.isEmpty { content }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks) { b in
                switch b {
                case .prose(_, let a): Text(a).fixedSize(horizontal: false, vertical: true)
                case .code(_, let a):
                    Text(a).fixedSize(horizontal: false, vertical: true)
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: .rect(cornerRadius: 8))
                }
            }
        }
        .textSelection(.enabled)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Documentation of a Typst built-in: a Liquid Glass panel below the caret, closed by Esc or a click elsewhere.
@MainActor final class DocsPanel: NSObject, NSWindowDelegate {
    static let shared = DocsPanel()
    private var panel: DocsKeyPanel?
    private weak var parent: NSWindow?
    private static let minWidth: CGFloat = 300, maxWidth: CGFloat = 640, maxHeight: CGFloat = 480

    /// `caret` is in screen coordinates; the panel goes below it, or above when the screen has no room.
    func show(doc: BuiltinDoc, signature: String? = nil, tip: AttributedString? = nil, caret: NSRect, in window: NSWindow) {
        close()
        parent = window
        let blocks = DocsBlock.parse(doc.docs)
        let signature = signature.map(SignatureText.attributed)
        let open: (URL) -> Void = { [weak self] url in
            self?.close()
            window.makeKeyAndOrderFront(nil)
            NSWorkspace.shared.open(url)
        }
        // Fit the content: as wide as its longest unwrapped line (within limits), then as tall as it is at that width.
        let view = DocsView(doc: doc, signature: signature, tip: tip, blocks: blocks, scrolls: false, open: { _ in })
        let ideal = NSHostingView(rootView: view.fixedSize()).fittingSize
        let measure = NSHostingController(rootView: view)
        let width = min(max(ideal.width, Self.minWidth), Self.maxWidth).rounded(.up)
        let natural = measure.sizeThatFits(in: CGSize(width: width, height: 10_000)).height
        let size = NSSize(width: width, height: min(natural, Self.maxHeight).rounded(.up))
        let panel = DocsKeyPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.styleAsGlass()
        panel.hidesOnDeactivate = true
        panel.delegate = self
        panel.onEscape = { [weak self] in self?.close(); window.makeKeyAndOrderFront(nil) }
        let glass = NSGlassEffectView()
        glass.cornerRadius = 18
        let host = NSHostingView(rootView: DocsView(doc: doc, signature: signature, tip: tip, blocks: blocks, scrolls: true, open: open))
        host.sizingOptions = []                    // the panel's frame is computed above; the view must not resize the window
        glass.contentView = host
        panel.contentView = glass
        let screen = (window.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        var origin = NSPoint(x: caret.minX - 16, y: caret.minY - size.height - 4)
        if origin.y < screen.minY { origin.y = caret.maxY + 4 }
        origin.x = min(max(origin.x, screen.minX), screen.maxX - size.width)
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
        window.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func close() {
        guard let panel else { return }
        self.panel = nil
        panel.delegate = nil
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) { close() }
}
