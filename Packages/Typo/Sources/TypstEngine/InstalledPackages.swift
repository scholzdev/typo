import Foundation

public struct InstalledPackage: Identifiable, Hashable, Sendable {
    public let namespace, name, version: String
    public let url: URL
    public let bytes: Int64
    public var id: String { "\(namespace)/\(name):\(version)" }

    /// Walks `<dir>/<namespace>/<name>/<version>`, sorted by namespace, name, version. A missing `dir` gives [].
    public static func list(in dir: URL, namespaces: Set<String>? = nil, measured: Bool = true) -> [InstalledPackage] {
        let fm = FileManager.default
        func subdirs(_ url: URL) -> [URL] {
            let items = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
            return items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        }
        var out: [InstalledPackage] = []
        for ns in subdirs(dir) where namespaces?.contains(ns.lastPathComponent) ?? true { for name in subdirs(ns) { for version in subdirs(name) {
            out.append(InstalledPackage(namespace: ns.lastPathComponent, name: name.lastPathComponent,
                                        version: version.lastPathComponent, url: version, bytes: measured ? DiskUsage.bytes(of: version) : 0))
        } } }
        return out.sorted {
            ($0.namespace, $0.name) != ($1.namespace, $1.name) ? ($0.namespace, $0.name) < ($1.namespace, $1.name)
                : $0.version.compare($1.version, options: .numeric) == .orderedAscending   // 0.2.0 before 0.10.0
        }
    }
}

public enum DiskUsage {
    /// Allocated bytes of a file, or of everything below a folder (hidden files count). Missing gives 0.
    public static func bytes(of url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileSizeKey]
        func size(_ f: URL) -> Int64 {
            let v = try? f.resourceValues(forKeys: Set(keys))
            return Int64(v?.totalFileAllocatedSize ?? v?.fileSize ?? 0)
        }
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
              let walk = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else { return size(url) }
        var total: Int64 = 0
        for case let f as URL in walk { total += size(f) }
        return total
    }
}
