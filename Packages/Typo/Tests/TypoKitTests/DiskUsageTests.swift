import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite struct DiskUsageTests {
    @Test func countsNestedAndHiddenFilesAndMissingIsZero() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root.appending(path: "a/b"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: root.appending(path: "a/b/f.txt"))
        let visible = DiskUsage.bytes(of: root)
        #expect(visible > 0)
        try Data("x".utf8).write(to: root.appending(path: ".hidden"))
        #expect(DiskUsage.bytes(of: root) > visible)
        #expect(DiskUsage.bytes(of: root.appending(path: ".hidden")) > 0)
        #expect(DiskUsage.bytes(of: root.appending(path: "missing")) == 0)
    }

    @Test func retentionDescriptionDerivesFromConstants() {
        let text = LocalHistory.retentionDescription
        #expect(text.contains("\(Int(LocalHistory.keepAllFor / 3600)) hours"))
        #expect(text.contains("\(LocalHistory.keepDailyDays) days"))
        #expect(text.contains("\(LocalHistory.maxCount)"))
    }

    @Test func snapshotFoldersLiveUnderTheRoot() {
        #expect(LocalHistory.folder(for: URL(filePath: "/tmp/p")).deletingLastPathComponent().path == LocalHistory.rootFolder.path)
    }

    @Test func embeddedFontsAreListed() {
        #expect(EngineVersions.embeddedFonts.files == 17)
    }
}
