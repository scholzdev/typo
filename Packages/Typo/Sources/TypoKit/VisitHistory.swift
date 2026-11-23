/// Back/forward history over visited items, like a browser's: a visit after going back drops the forward part.
public struct VisitHistory<Item: Equatable>: Sendable where Item: Sendable {
    private var items: [Item]
    private var index: Int

    public init(start: Item) { items = [start]; index = 0 }

    public var current: Item { items[index] }
    public var canGoBack: Bool { index > 0 }
    public var canGoForward: Bool { index < items.count - 1 }

    public mutating func visit(_ item: Item) {
        guard item != current else { return }
        items.removeSubrange((index + 1)...)
        items.append(item)
        index += 1
    }

    public mutating func back() -> Item? {
        guard canGoBack else { return nil }
        index -= 1
        return current
    }

    public mutating func forward() -> Item? {
        guard canGoForward else { return nil }
        index += 1
        return current
    }
}
