import Foundation

/// Project-relative path ("chapters/intro.typ"). The only file identity in the app and in the ABI.
/// Validated once at construction: '/'-separated, no leading '/', no '.', no '..', no empty components.
public struct RelPath: Hashable, Sendable, Codable {
    public let raw: String
    public init?(_ raw: String) {
        guard !raw.isEmpty, !raw.hasPrefix("/") else { return nil }
        let parts = raw.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.contains(where: { $0.isEmpty || $0 == ".." || $0 == "." }) else { return nil }
        self.raw = raw
    }
}

extension RelPath {
    /// The last component.
    public var name: String { String(raw.split(separator: "/").last!) }
    /// The folder holding it; nil for the project root.
    public var parent: RelPath? { raw.lastIndex(of: "/").flatMap { RelPath(String(raw[..<$0])) } }
    /// `name` inside `folder` (nil = the project root); nil if the result is not a valid path.
    public static func make(_ name: String, in folder: RelPath?) -> RelPath? { RelPath(folder.map { $0.raw + "/" + name } ?? name) }
    public func isAtOrUnder(_ p: RelPath) -> Bool { raw == p.raw || raw.hasPrefix(p.raw + "/") }
    /// The path after `old` became `new`; nil when this path is not at or under `old`.
    public func replacing(_ old: RelPath, with new: RelPath) -> RelPath? {
        isAtOrUnder(old) ? RelPath(new.raw + raw.dropFirst(old.raw.count)) : nil
    }
}

/// Stable window identity. SwiftUI stores it for restoration and refocuses equal values.
public struct ProjectID: Hashable, Sendable, Codable {
    let uuid: UUID
    public init() { uuid = UUID() }
    public var raw: String { uuid.uuidString }
}
