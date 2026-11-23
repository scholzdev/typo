import Foundation
import Testing
@testable import TypstEngine

@Suite struct InstalledPackageTests {
    @Test func listsSortedAndSkipsNoise() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        for p in ["preview/zeta/0.1.0", "preview/alpha/0.2.0", "preview/alpha/0.10.0", "local/tool/1.0.0", ".hidden/x/1.0.0"] {
            let d = root.appending(path: p)
            try fm.createDirectory(at: d, withIntermediateDirectories: true)
            try Data("hello".utf8).write(to: d.appending(path: "typst.toml"))
        }
        try Data("x".utf8).write(to: root.appending(path: "preview/stray.txt"))
        try Data("x".utf8).write(to: root.appending(path: "loose.txt"))

        let list = InstalledPackage.list(in: root)
        #expect(list.map(\.id) == ["local/tool:1.0.0", "preview/alpha:0.2.0", "preview/alpha:0.10.0", "preview/zeta:0.1.0"])
        #expect(list.allSatisfy { $0.bytes > 0 })
        #expect(InstalledPackage.list(in: root.appending(path: "missing")).isEmpty)
    }
}
