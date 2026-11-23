import Foundation
import Testing
@testable import TypoKit

@Suite struct DefaultsMigrationTests {
    @Test func copiesMissingKeysWithoutOverwritingAndRunsOnce() throws {
        let old = "typo-old-\(UUID().uuidString)", new = "typo-new-\(UUID().uuidString)"
        let source = try #require(UserDefaults(suiteName: old)), defaults = try #require(UserDefaults(suiteName: new))
        defer { source.removePersistentDomain(forName: old); defaults.removePersistentDomain(forName: new) }
        source.set(18, forKey: "editorFontSize")
        source.set("old", forKey: "editorTheme")
        defaults.set("kept", forKey: "editorTheme")

        DefaultsMigration.run(from: old, into: defaults, marker: "m")
        #expect(defaults.integer(forKey: "editorFontSize") == 18)
        #expect(defaults.string(forKey: "editorTheme") == "kept")
        #expect(source.integer(forKey: "editorFontSize") == 18)   // old domain untouched

        source.set(1, forKey: "later")
        DefaultsMigration.run(from: old, into: defaults, marker: "m")
        #expect(defaults.object(forKey: "later") == nil)
    }

    @Test func emptyOldDomainStillSetsTheMarker() throws {
        let new = "typo-new-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: new))
        defer { defaults.removePersistentDomain(forName: new) }
        DefaultsMigration.run(from: "typo-none-\(UUID().uuidString)", into: defaults, marker: "m")
        #expect(defaults.bool(forKey: "m"))
    }
}
