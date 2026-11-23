import Testing
import Foundation
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite struct UniverseTests {
    static func fixture() throws -> [UniversePackage] {
        Universe.parse(try Data(contentsOf: TestEnv.fixtures.appending(path: "package-index/real-index-2026-11-17.json")))
    }

    @Test func realIndexHasUniqueNamesNewestFirst() throws {
        let all = try Self.fixture()
        #expect(all.count > 1000)
        #expect(Set(all.map(\.name)).count == all.count)
        for p in all {
            #expect(p.allVersions.first == p.version)
            #expect(zip(p.allVersions, p.allVersions.dropFirst()).allSatisfy { Universe.isNewer($0, than: $1) })
        }
        #expect(all.contains { $0.isTemplate })
    }

    @Test func versionsCompareNumerically() {
        #expect(Universe.isNewer("0.10.0", than: "0.2.0"))
        #expect(!Universe.isNewer("0.2.0", than: "0.10.0"))
        let json = #"[{"name":"x","version":"0.2.0"},{"name":"x","version":"0.10.0"}]"#
        #expect(Universe.parse(Data(json.utf8)).first?.allVersions == ["0.10.0", "0.2.0"])
    }

    @Test func detailFieldsComeFromTheNewestVersion() {
        let json = #"[{"name":"x","version":"0.1.0","compiler":"0.11.0","updatedAt":1700000000},{"name":"x","version":"0.2.0","compiler":"0.13.0","updatedAt":1704708827}]"#
        let p = Universe.parse(Data(json.utf8))[0]
        #expect(p.compiler == "0.13.0" && p.updated == Date(timeIntervalSince1970: 1704708827))
        #expect(Universe.needsNewerTypst(p, than: "0.12.0") && !Universe.needsNewerTypst(p, than: "0.13.0") && !Universe.needsNewerTypst(p, than: "0.14.1"))
        let old = Universe.parse(Data(#"[{"name":"y","version":"1.0.0"}]"#.utf8))[0]
        #expect(old.compiler == nil && old.updated == nil && !Universe.needsNewerTypst(old, than: "0.1.0"))
    }

    @Test func searchNeedsAllWordsCaseInsensitive() {
        let json = #"[{"name":"cetz","version":"1.0.0","description":"Drawing library","keywords":["Canvas"]}]"#
        let p = Universe.parse(Data(json.utf8))[0]
        #expect(Universe.matches(p, query: "DRAW canvas"))
        #expect(Universe.matches(p, query: "  "))
        #expect(!Universe.matches(p, query: "draw plot"))
    }

    @Test func installState() {
        let p = Universe.parse(Data(#"[{"name":"x","version":"0.10.0"}]"#.utf8))[0]
        #expect(Universe.state(of: p, installed: []) == .get)
        #expect(Universe.state(of: p, installed: ["0.2.0"]) == .update)
        #expect(Universe.state(of: p, installed: ["0.2.0", "0.10.0"]) == .installed)
    }
}
