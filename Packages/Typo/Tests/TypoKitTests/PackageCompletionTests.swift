import Foundation
import Synchronization
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

private let fixtureIndex = """
[
 {"name":"cetz","version":"0.3.0","description":"Drawing, old","compiler":"0.12.0"},
 {"name":"cetz","version":"0.4.2","description":"Drawing, new","compiler":"0.13.0"},
 {"name":"cetz","version":"0.5.0","description":"Drawing, too new","compiler":"99.0.0"},
 {"name":"future","version":"1.0.0","description":"Needs a newer compiler","compiler":"99.0.0"},
 {"name":"plain","version":"1.2.3"},
 {"garbage":true}
]
"""

@Suite(.serialized) @MainActor struct PackageCompletionTests {
    // 1
    @Test func completionListsOnlyCompatibleNewestVersionsWithDescriptions() async throws {
        let rt = try await TestEnv.runtime(packageIndex: Data(fixtureIndex.utf8))
        let (p, _) = try await TestEnv.project(files: ["main.typ": "#import \"@\""], runtime: rt)
        let b = try await p.open(RelPath("main.typ")!)
        let list = try #require(await p.complete(in: b.path, at: 10, explicit: false))
        // labels are quoted, as typst-ide labels string completions
        let pkgs = list.items.filter { $0.kind == .package }
        #expect(pkgs.map(\.label).sorted() == ["\"@preview/cetz:0.4.2\"", "\"@preview/plain:1.2.3\""])
        #expect(pkgs.first { $0.label.contains("cetz") }?.detail == "Drawing, new")
        #expect(pkgs.first { $0.label.contains("plain") }?.detail == nil)
    }

    // 3: typing goes through the pair decisions, as the editor does.
    @Test func acceptAfterAutoPairedQuoteDoesNotDoubleIt() async throws {
        let rt = try await TestEnv.runtime(packageIndex: Data(fixtureIndex.utf8))
        let (p, _) = try await TestEnv.project(files: ["main.typ": ""], runtime: rt)
        let b = try await p.open(RelPath("main.typ")!)
        var caret = 0
        var auto = Set<Int>()
        for ch in "#import \"@ce" {
            let s = String(ch)
            let sel = NSRange(location: caret, length: 0)
            switch PairEdit.decide(typed: s, text: b.storage.string, selection: sel, mode: b.syntax.mode(at: caret), autoInserted: auto) {
            case .edit(let range, let replacement, let selection, let closer):
                replace(b, range, with: replacement)
                caret = selection.location
                if let closer { auto.insert(closer) }
            default:
                replace(b, sel, with: s)
                caret += 1
            }
        }
        #expect(b.storage.string == "#import \"@ce\"")
        let list = try #require(await p.complete(in: b.path, at: caret, explicit: false))
        let live = try #require(p.live(list, caret: caret))
        let item = try #require(live.items.first { $0.label.hasPrefix("\"@preview/cetz") })
        replace(b, live.range, with: Snippet.parse(item.apply ?? item.label).text)
        #expect(b.storage.string == "#import \"@preview/cetz:0.4.2\"")
    }

    // 4
    @Test func timing() async throws {
        let json = try Data(contentsOf: TestEnv.fixtures.appending(path: "package-index/real-index-2026-11-17.json"))
        let rt = try await TestEnv.runtime(packageIndex: Data("[]".utf8))
        let t0 = ContinuousClock.now
        let kept = Bridge.setPackageIndex(rt.handle, json: json)
        let setMs = Self.ms(ContinuousClock.now - t0)

        let (p, _) = try await TestEnv.project(files: ["main.typ": "#import \"@\""], runtime: rt)
        let b = try await p.open(RelPath("main.typ")!)
        _ = await p.settle()
        var samples: [Double] = []
        var items: [CompletionItem] = []
        for _ in 0..<15 {
            let t = ContinuousClock.now
            let l = await p.complete(in: b.path, at: 10, explicit: false)
            samples.append(Self.ms(ContinuousClock.now - t))
            items = l?.items ?? []
        }
        #expect(items.contains { $0.label.hasPrefix("\"@preview/cetz:") })     // smoke: the real index has cetz
        #if DEBUG
        let profile = "debug"
        #else
        let profile = "release"
        #endif
        print("PACKAGE INDEX TIMING [\(profile)] set_package_index: \(String(format: "%.1f", setMs)) ms (\(kept) kept); "
              + "completion at #import \"@|\": median \(String(format: "%.1f", samples.sorted()[7])) ms (\(items.count) items)")
    }

    static func ms(_ d: Duration) -> Double { Double(d.components.seconds) * 1e3 + Double(d.components.attoseconds) / 1e15 }
}

// 2: PackageIndex with an injected fetcher; apply is a stub that records what the runtime would receive.
@Suite(.serialized) struct PackageIndexTests {
    final class Probe: Sendable {
        let applied = Mutex<[String]>([])
        let etags = Mutex<[String?]>([])
        let clock = Mutex(Date(timeIntervalSince1970: 1_000_000))
        var now: Date { clock.withLock { $0 } }
    }

    func make(cached: String?, ageSeconds: TimeInterval = 0, fetch: @escaping PackageIndex.Fetcher)
        throws -> (PackageIndex, Probe, URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "pkgindex-\(UUID().uuidString)/preview")
        let probe = Probe()
        if let cached {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try cached.write(to: dir.appending(path: "index.json"), atomically: true, encoding: .utf8)
            try "\"old\"".write(to: dir.appending(path: "index.etag"), atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: probe.now.addingTimeInterval(-ageSeconds)],
                                                  ofItemAtPath: dir.appending(path: "index.json").path)
        }
        let index = PackageIndex(dir: dir, fetch: { tag in probe.etags.withLock { $0.append(tag) }; return try await fetch(tag) },
                                 now: { probe.now }, apply: { d in
            let s = String(decoding: d, as: UTF8.self)
            probe.applied.withLock { $0.append(s) }
            return s == "garbage" ? 0 : 1
        })
        return (index, probe, dir)
    }
    func read(_ dir: URL, _ name: String) -> String? { try? String(contentsOf: dir.appending(path: name), encoding: .utf8) }
    struct Offline: Error {}

    @Test func loadsFromCacheAndSkipsRevalidationWhenFresh() async throws {
        let (index, probe, _) = try make(cached: "cached", ageSeconds: 60) { _ in throw Offline() }
        #expect(index.loadCache() == 1)
        #expect(probe.applied.withLock { $0 } == ["cached"])
        await index.revalidate()
        #expect(probe.etags.withLock { $0 }.isEmpty)
    }

    @Test func networkFailureKeepsTheCache() async throws {
        let (index, probe, dir) = try make(cached: "cached", ageSeconds: 7200) { _ in throw Offline() }
        index.loadCache()
        await index.revalidate()
        #expect(probe.etags.withLock { $0 } == ["\"old\""])
        #expect(read(dir, "index.json") == "cached")
        #expect(!index.isFresh)                                  // a failed check does not count as a check
    }

    @Test func notModifiedKeepsTheCacheAndRestartsTheHour() async throws {
        let (index, probe, dir) = try make(cached: "cached", ageSeconds: 7200) { _ in .notModified }
        index.loadCache()
        await index.revalidate()
        #expect(read(dir, "index.json") == "cached")
        #expect(probe.applied.withLock { $0 } == ["cached"])
        #expect(index.isFresh)
    }

    @Test func okReplacesTheCacheAndStoresTheEtag() async throws {
        let (index, probe, dir) = try make(cached: "cached", ageSeconds: 7200) { _ in .data(Data("new".utf8), etag: "\"new\"") }
        index.loadCache()
        await index.revalidate()
        #expect(probe.applied.withLock { $0 } == ["cached", "new"])
        #expect(read(dir, "index.json") == "new")
        #expect(read(dir, "index.etag") == "\"new\"")
        #expect(index.isFresh)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() == ["index.etag", "index.json"])   // no temp files left
    }

    @Test func okWithoutAnIndexKeepsTheCache() async throws {
        let (index, _, dir) = try make(cached: "cached", ageSeconds: 7200) { _ in .data(Data("garbage".utf8), etag: "\"x\"") }
        await index.revalidate()
        #expect(read(dir, "index.json") == "cached")
        #expect(read(dir, "index.etag") == "\"old\"")
    }

    @Test func noCacheAndFailureIsEmpty() async throws {
        let (index, probe, dir) = try make(cached: nil) { _ in throw Offline() }
        #expect(index.loadCache() == 0)
        await index.revalidate()
        #expect(probe.etags.withLock { $0 } == [nil])
        #expect(probe.applied.withLock { $0 }.isEmpty)
        #expect(read(dir, "index.json") == nil)
    }
}
