import AppKit
import TypoKit
import TypstEngine

/// The completion list: a borderless, non-activating child panel, so the text view keeps first responder
/// and every key. It never takes focus; the editor's delegate forwards the navigation keys.
@MainActor final class CompletionPopup: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var onPick: ((CompletionItem) -> Void)?
    private(set) var items: [CompletionItem] = []
    var isVisible: Bool { panel.isVisible }
    var selected: CompletionItem? { items.indices.contains(table.selectedRow) ? items[table.selectedRow] : nil }

    private static var rowHeight: CGFloat { max(24, Highlighter.fontSize + 11) }   // follows the editor font size
    private static let maxRows = 10, width: CGFloat = 380, inset: CGFloat = 4, detailHeight: CGFloat = 40
    private let panel = GlassChildPanel(cornerRadius: 12)
    private let table = NSTableView()
    private let detail = NSTextField(wrappingLabelWithString: "")
    private var typed = ""                          // what the user typed into the replaced range: its matches are bold

    override init() {
        super.init()
        let effect = panel.content

        let column = NSTableColumn(identifier: .init("item"))
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .plain
        table.backgroundColor = .clear
        table.intercellSpacing = .zero
        table.rowHeight = Self.rowHeight
        table.allowsEmptySelection = false
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clicked)

        let scroll = NSScrollView.overlay(table)
        effect.addSubview(scroll)
        let rule = NSBox()
        rule.boxType = .separator
        rule.translatesAutoresizingMaskIntoConstraints = false
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.maximumNumberOfLines = 2
        detail.lineBreakMode = .byTruncatingTail
        detail.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(rule)
        effect.addSubview(detail)
        NSLayoutConstraint.activate([
            rule.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            rule.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -Self.detailHeight),
            detail.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 10),
            detail.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -10),
            detail.topAnchor.constraint(equalTo: rule.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: Self.inset),
            scroll.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -Self.inset),
            scroll.topAnchor.constraint(equalTo: effect.topAnchor, constant: Self.inset),
            scroll.bottomAnchor.constraint(equalTo: rule.topAnchor),
        ])
    }

    /// Shows `items` under the caret line of `textView`, with the list's left edge at the start of `range`.
    func show(_ newItems: [CompletionItem], range: NSRange, in textView: NSTextView) {
        guard let window = textView.window else { return }
        let newTyped = (textView.string as NSString).substring(with: range)
        let changed = newItems != items || newTyped != typed
        items = newItems
        typed = newTyped
        if changed {
            table.rowHeight = Self.rowHeight
            table.reloadData()
            table.selectRowIndexes([0], byExtendingSelection: false)
            table.scrollRowToVisible(0)
            showDetail()
        }
        let rows = min(items.count, Self.maxRows)
        let size = NSSize(width: Self.width, height: CGFloat(rows) * Self.rowHeight + 2 * Self.inset + Self.detailHeight)
        let start = textView.firstRect(forCharacterRange: NSRange(location: range.location, length: 0), actualRange: nil)
        let caret = textView.firstRect(forCharacterRange: NSRange(location: NSMaxRange(range), length: 0), actualRange: nil)
        panel.show(size: size, x: start.minX - Self.inset - 20, belowY: caret.minY, aboveY: caret.maxY, in: window, appearance: textView.effectiveAppearance)
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.hide()
        items = []
    }

    /// Moves the selection, clamped to the ends.
    func move(by delta: Int) {
        guard !items.isEmpty else { return }
        let row = min(max(table.selectedRow + delta, 0), items.count - 1)
        table.selectRowIndexes([row], byExtendingSelection: false)
        reveal(row)
        showDetail()
    }

    /// `scrollRowToVisible` scrolls smoothly, and with a held arrow key the list fell behind the selection; this jumps.
    private func reveal(_ row: Int) {
        guard let scroll = table.enclosingScrollView else { return table.scrollRowToVisible(row) }
        let clip = scroll.contentView, r = table.rect(ofRow: row)
        var origin = clip.bounds.origin
        let top = origin.y + clip.contentInsets.top, bottom = origin.y + clip.bounds.height - clip.contentInsets.bottom
        if r.minY < top { origin.y = r.minY - clip.contentInsets.top }
        else if r.maxY > bottom { origin.y = r.maxY - clip.bounds.height + clip.contentInsets.bottom }
        else { return }
        clip.setBoundsOrigin(origin)
        scroll.reflectScrolledClipView(clip)
    }

    /// The area under the list: the first sentence of the selected item's docs, or a label's content ("P = NP").
    private func showDetail() {
        guard let item = selected else { return detail.stringValue = "" }
        detail.stringValue = (item.kind == .label ? item.detail : item.summary) ?? ""
    }

    var pageSize: Int { Self.maxRows - 1 }

    @objc private func clicked() {
        if items.indices.contains(table.clickedRow) { onPick?(items[table.clickedRow]) }
    }

    func tableViewSelectionDidChange(_ notification: Notification) { showDetail() }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { CompletionRowView() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: CompletionCell.id, owner: nil) as? CompletionCell ?? CompletionCell()
        cell.identifier = CompletionCell.id
        cell.configure(items[row], typed: typed)
        return cell
    }
}

/// The selection highlight of a menu: a rounded accent fill with white text, also in a non-key panel.
private final class CompletionRowView: NSTableRowView {
    override var isEmphasized: Bool { get { true } set {} }
    override var interiorBackgroundStyle: NSView.BackgroundStyle { isSelected ? .emphasized : .normal }

    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 5, yRadius: 5).fill()
    }
}

private final class CompletionCell: NSTableCellView {
    static let id = NSUserInterfaceItemIdentifier("completion")
    private let badge = NSView()
    private let badgeText = NSTextField(labelWithString: "")
    private let glyph = NSTextField(labelWithString: "")
    private let label = NSTextField(labelWithString: "")
    private var text = "", matches: [Int] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 4
        badge.layer?.cornerCurve = .continuous
        badgeText.font = .systemFont(ofSize: 10, weight: .bold)
        badgeText.textColor = .white
        badgeText.alignment = .center
        glyph.alignment = .center
        glyph.font = .systemFont(ofSize: 14)
        label.lineBreakMode = .byTruncatingTail
        let lead = NSView()                                    // badge and glyph share one fixed slot
        for v in [badge, glyph] { v.translatesAutoresizingMaskIntoConstraints = false; lead.addSubview(v) }
        badgeText.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(badgeText)
        let stack = NSStackView(views: [lead, label])
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            lead.widthAnchor.constraint(equalToConstant: 22),
            badge.widthAnchor.constraint(equalToConstant: 22), badge.heightAnchor.constraint(equalToConstant: 16),
            badge.centerXAnchor.constraint(equalTo: lead.centerXAnchor), badge.centerYAnchor.constraint(equalTo: lead.centerYAnchor),
            badgeText.centerXAnchor.constraint(equalTo: badge.centerXAnchor), badgeText.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            glyph.centerXAnchor.constraint(equalTo: lead.centerXAnchor), glyph.centerYAnchor.constraint(equalTo: lead.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var backgroundStyle: NSView.BackgroundStyle { didSet { renderLabel() } }

    private func renderLabel() {
        let color: NSColor = backgroundStyle == .emphasized ? .selectedMenuItemTextColor : .labelColor
        let out = NSMutableAttributedString(string: text, attributes: [.font: NSFont.monospacedSystemFont(ofSize: Highlighter.fontSize - 1, weight: .regular), .foregroundColor: color])
        let chars = Array(text.indices)
        for i in matches where chars.indices.contains(i) {
            out.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: Highlighter.fontSize - 1, weight: .bold), range: NSRange(chars[i]...chars[i], in: text))
        }
        label.attributedStringValue = out
        glyph.textColor = color
    }

    private static func color(_ tint: CompletionBadge.Tint) -> NSColor {
        switch tint {
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .orange: .systemOrange
        case .green: .systemGreen
        case .teal: .systemTeal
        case .pink: .systemPink
        case .indigo: .systemIndigo
        case .brown: .systemBrown
        case .gray: .systemGray
        }
    }

    func configure(_ item: CompletionItem, typed: String) {
        text = item.label
        matches = CompletionMatch.indices(of: typed, in: item.label)
        if case .symbol(let g) = item.kind { glyph.stringValue = g }
        let letters = CompletionBadge.letters(for: item.kind)
        badge.isHidden = letters == nil
        glyph.isHidden = letters != nil
        badgeText.stringValue = letters ?? ""
        badge.layer?.backgroundColor = Self.color(CompletionBadge.tint(for: item.kind)).cgColor
        renderLabel()
    }
}
