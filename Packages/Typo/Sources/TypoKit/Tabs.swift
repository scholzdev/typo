import Foundation
import TypstEngine

/// The tabs of one editor pane (design/14h): ordered files plus at most one "preview" tab, shown in italics, that the
/// next non-permanent open replaces. Which tab is shown is not stored here: it is the pane's file.
public struct TabList: Equatable, Sendable, Codable {
    public private(set) var paths: [RelPath] = []
    public private(set) var preview: RelPath?
    /// Pinned tabs sit first in `paths`, in the order they were pinned; they are never the preview and never close.
    public private(set) var pinned: [RelPath] = []

    public init() {}

    public func contains(_ p: RelPath) -> Bool { paths.contains(p) }

    /// The file name; the folder is appended when another tab has the same name.
    public func title(of p: RelPath) -> String {
        guard paths.contains(where: { $0 != p && $0.name == p.name }), let parent = p.parent else { return p.name }
        return "\(p.name) — \(parent.name)"
    }

    /// Makes `path` a tab. An existing tab only changes state when `permanent` (its preview state ends).
    /// A new preview tab replaces the current one in place; a new permanent tab goes right after `active`.
    public mutating func show(_ path: RelPath, permanent: Bool, active: RelPath? = nil, pinning: NavigationSettings.TabPinning = .manually) {
        let permanent = permanent || pinning == .automatically
        if paths.contains(path) {
            if permanent { makePermanent(path) }
            return
        }
        if permanent {
            paths.insert(path, at: max(pinned.count, active.flatMap { paths.firstIndex(of: $0) }.map { $0 + 1 } ?? paths.endIndex))
        } else if let old = preview, let i = paths.firstIndex(of: old) {
            paths[i] = path
            preview = path
        } else {
            paths.append(path)
            preview = path
        }
    }

    /// The tab `offset` places from `active`, wrapping around; nil without tabs.
    public func neighbour(of active: RelPath?, by offset: Int) -> RelPath? {
        guard !paths.isEmpty else { return nil }
        let i = active.flatMap { paths.firstIndex(of: $0) } ?? 0
        return paths[((i + offset) % paths.count + paths.count) % paths.count]
    }

    /// The preview tab becomes a normal one.
    public mutating func makePermanent(_ path: RelPath) { if preview == path { preview = nil } }

    /// Moves the tab behind the other pinned tabs; it stops being the preview.
    public mutating func pin(_ path: RelPath) {
        guard paths.contains(path), !pinned.contains(path) else { return }
        makePermanent(path)
        paths.removeAll { $0 == path }
        paths.insert(path, at: pinned.count)
        pinned.append(path)
    }

    /// The tab becomes the first unpinned one.
    public mutating func unpin(_ path: RelPath) {
        guard pinned.contains(path) else { return }
        pinned.removeAll { $0 == path }
        paths.removeAll { $0 == path }
        paths.insert(path, at: pinned.count)
    }

    /// Removes the tab; returns the file to show: `active` itself unless it was the closed one, then the right
    /// neighbour, else the left one, else nil. A pinned tab stays.
    public mutating func close(_ path: RelPath, active: RelPath?) -> RelPath? {
        if pinned.contains(path) { return active }
        return remove(active: active) { $0 == path }
    }

    /// Drops every tab at or under `path`; returns the file to show as `close` does.
    public mutating func remove(atOrUnder path: RelPath, active: RelPath?) -> RelPath? {
        remove(active: active) { $0.isAtOrUnder(path) }
    }

    /// The tabs at or under `old` follow a move to `new`.
    public mutating func rekey(from old: RelPath, to new: RelPath) {
        var seen = Set<RelPath>()
        paths = paths.map { $0.replacing(old, with: new) ?? $0 }.filter { seen.insert($0).inserted }
        preview = preview.map { $0.replacing(old, with: new) ?? $0 }
        var seenPinned = Set<RelPath>()
        pinned = pinned.map { $0.replacing(old, with: new) ?? $0 }.filter { paths.contains($0) && seenPinned.insert($0).inserted }
    }

    private mutating func remove(active: RelPath?, where gone: (RelPath) -> Bool) -> RelPath? {
        let before = active.flatMap { paths.firstIndex(of: $0) }.map { i in paths[..<i].filter { !gone($0) }.count }
        paths.removeAll(where: gone)
        pinned.removeAll(where: gone)
        if let p = preview, !paths.contains(p) { preview = nil }
        guard let active, gone(active) else { return active }
        guard let k = before else { return nil }
        return paths.indices.contains(k) ? paths[k] : paths.last
    }

    private enum CodingKeys: String, CodingKey { case paths, preview, pinned }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        paths = try c.decode([String].self, forKey: .paths).compactMap(RelPath.init)
        preview = (try c.decodeIfPresent(String.self, forKey: .preview)).flatMap(RelPath.init)
        if let p = preview, !paths.contains(p) { preview = nil }
        let saved = (try c.decodeIfPresent([String].self, forKey: .pinned) ?? []).compactMap(RelPath.init)
        for p in saved where paths.contains(p) { pin(p) }   // old data has no key
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(paths.map(\.raw), forKey: .paths)
        try c.encodeIfPresent(preview?.raw, forKey: .preview)
        try c.encode(pinned.map(\.raw), forKey: .pinned)
    }
}

extension Project {
    // persisted key, kept from the app's old name so saved data survives
    private var tabsKey: String { "Tympan.tabs.\(id.raw)" }

    func saveTabs() {
        UserDefaults.standard.set(try? JSONEncoder().encode(tabs), forKey: tabsKey)
    }

    /// The saved tabs minus files that no longer exist.
    func restoredTabs() -> TabList {
        guard let data = UserDefaults.standard.data(forKey: tabsKey), let saved = try? JSONDecoder().decode(TabList.self, from: data) else { return TabList() }
        var list = TabList()
        for p in saved.paths where exists(p) && !isDirectory(p) { list.show(p, permanent: saved.preview != p) }
        for p in saved.pinned where list.contains(p) { list.pin(p) }
        if !list.paths.isEmpty, !list.contains(main), exists(main) { list.show(main, permanent: true) }   // main is shown at open
        return list
    }
}
