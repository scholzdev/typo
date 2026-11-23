import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

/// Answers each request from `route` and records it; nothing reaches the network.
private final class ZoteroStub: @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    var requests: [URLRequest] { lock.withLock { _requests } }
    let route: @Sendable (URLRequest) throws -> ZoteroResponse

    init(_ route: @escaping @Sendable (URLRequest) throws -> ZoteroResponse) { self.route = route }

    var transport: ZoteroTransport {
        { req in
            self.lock.withLock { self._requests.append(req) }
            return try self.route(req)
        }
    }
}

private func query(_ r: URLRequest, _ name: String) -> String? {
    URLComponents(url: r.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
}

private let bibA = "\n@article{smith2020,\n\ttitle = {Alpha},\n\tauthor = {Smith, Ann},\n\tyear = {2020},\n}\n"
private let bibB = "\n@book{jones2021,\n\ttitle = {Beta},\n\tauthor = {Jones, Bob},\n\tyear = {2021},\n}\n"

@Suite struct ZoteroClientTests {
    @Test func localReadsTheLibraryAndCollections() async throws {
        let stub = ZoteroStub { r in
            let path = r.url!.path()
            if path.hasSuffix("/collections") {
                let json = #"[{"key":"AAA","data":{"name":"Thesis","parentCollection":false}},{"key":"BBB","data":{"name":"Ch 1","parentCollection":"AAA"}}]"#
                return ZoteroResponse(status: 200, body: Data(json.utf8))
            }
            return ZoteroResponse(status: 200, body: Data((path.contains("/collections/BBB/") ? bibB : bibA).utf8))
        }
        let c = ZoteroClient(source: .local, userID: "123", key: nil, transport: stub.transport)
        #expect(try await c.collections() == [ZoteroCollection(key: "AAA", name: "Thesis"), ZoteroCollection(key: "BBB", name: "Thesis \u{203A} Ch 1")])
        #expect(try await c.bibtex(collection: nil, since: nil) == ZoteroExport(text: bibA, version: nil))
        #expect(try await c.bibtex(collection: "BBB", since: nil)?.text == bibB)
        let urls = stub.requests.map { $0.url!.absoluteString }
        #expect(urls == ["http://127.0.0.1:23119/api/users/0/collections",
                         "http://127.0.0.1:23119/api/users/0/items/top?format=bibtex",
                         "http://127.0.0.1:23119/api/users/0/collections/BBB/items/top?format=bibtex"])
        #expect(stub.requests.allSatisfy { $0.value(forHTTPHeaderField: "Zotero-API-Key") == nil && $0.value(forHTTPHeaderField: "Zotero-API-Version") == "3" })
    }

    @Test func localNotRunningOrDisabled() async {
        let down = ZoteroClient(source: .local, userID: "0", key: nil, transport: ZoteroStub { _ in throw URLError(.cannotConnectToHost) }.transport)
        await #expect(throws: ZoteroError.notRunning) { try await down.bibtex(collection: nil, since: nil) }
        for status in [403, 404] {
            let off = ZoteroClient(source: .local, userID: "0", key: nil, transport: ZoteroStub { _ in ZoteroResponse(status: status) }.transport)
            await #expect(throws: ZoteroError.localAPIDisabled) { try await off.collections() }
        }
        #expect(ZoteroError.localAPIDisabled.errorDescription!.contains("Allow other applications on this computer to communicate with Zotero"))
    }

    @Test func webPaginatesWithKeyAndVersion() async throws {
        let stub = ZoteroStub { r in
            let start = Int(query(r, "start") ?? "0")!
            return ZoteroResponse(status: 200, headers: ["total-results": "150", "last-modified-version": "42"], body: Data((start == 0 ? bibA : bibB).utf8))
        }
        let c = ZoteroClient(source: .web, userID: "123", key: "secret", transport: stub.transport)
        let export = try #require(try await c.bibtex(collection: nil, since: 7))
        #expect(export.text == bibA + "\n" + bibB && export.version == 42)
        #expect(stub.requests.map { query($0, "start") } == ["0", "100"])
        #expect(stub.requests.allSatisfy { $0.url!.absoluteString.hasPrefix("https://api.zotero.org/users/123/items/top?") && query($0, "limit") == "100" && query($0, "format") == "bibtex" })
        #expect(stub.requests.allSatisfy { $0.value(forHTTPHeaderField: "Zotero-API-Key") == "secret" && $0.value(forHTTPHeaderField: "Zotero-API-Version") == "3" })
        #expect(stub.requests.map { $0.value(forHTTPHeaderField: "If-Modified-Since-Version") } == ["7", nil])
    }

    @Test func webNotModifiedBadKeyAndRateLimit() async throws {
        let c304 = ZoteroClient(source: .web, userID: "1", key: "k", transport: ZoteroStub { _ in ZoteroResponse(status: 304) }.transport)
        #expect(try await c304.bibtex(collection: nil, since: 5) == nil)
        let c403 = ZoteroClient(source: .web, userID: "1", key: "bad", transport: ZoteroStub { _ in ZoteroResponse(status: 403) }.transport)
        await #expect(throws: ZoteroError.badKey) { try await c403.bibtex(collection: nil, since: nil) }
        let c429 = ZoteroClient(source: .web, userID: "1", key: "k", transport: ZoteroStub { _ in ZoteroResponse(status: 429, headers: ["retry-after": "30"]) }.transport)
        await #expect(throws: ZoteroError.rateLimited(seconds: 30)) { try await c429.bibtex(collection: nil, since: nil) }
        let noKey = ZoteroClient(source: .web, userID: "1", key: nil, transport: ZoteroStub { _ in ZoteroResponse(status: 200) }.transport)
        await #expect(throws: ZoteroError.missingKey) { try await noKey.collections() }
    }
}

@Suite(.serialized) @MainActor struct ZoteroSyncTests {
    private func rel(_ s: String) -> RelPath { RelPath(s)! }
    private func text(_ root: URL, _ path: String) throws -> String { try String(contentsOf: root.appending(path: path), encoding: .utf8) }

    @Test func writesOnlyTheTargetWithTheHeader() async throws {
        let files = ["main.typ": "= Hi\n#bibliography(\"refs.bib\")\n", "other.bib": "@misc{x, title = {X}}\n"]
        let (p, root) = try await TestEnv.project(files: files)
        defer { p.disconnectZotero() }
        await p.connectZotero(ZoteroLink(source: .local, userID: "", collection: nil, target: rel("refs.bib")))
        let stub = ZoteroStub { _ in ZoteroResponse(status: 200, body: Data((bibA + "\n" + bibB).utf8)) }
        let now = Date(timeIntervalSince1970: 1000)
        await p.syncZotero(key: nil, transport: stub.transport, now: now)
        #expect(p.zoteroError == nil)
        let written = try text(root, "refs.bib")
        #expect(written.hasPrefix(ZoteroLink.header + "\n"))
        #expect(BibTeX.entries(in: written).map(\.key) == ["smith2020", "jones2021"])
        let parsed = BibliographyFile.parse(rel("refs.bib"), text: written)       // the header must not break typst's parser
        #expect(parsed.error == nil && parsed.entries.map(\.key) == ["smith2020", "jones2021"])
        #expect(p.zoteroLink?.entryCount == 2 && p.zoteroLink?.lastSynced == now)
        #expect(p.allFiles.contains(rel("refs.bib")))
        for (name, content) in files { #expect(try text(root, name) == content) }
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        #expect(names == ["main.typ", "other.bib", "refs.bib"])

        // An open buffer follows a change as one undoable edit; unchanged text writes nothing.
        let b = try await p.open(rel("refs.bib"))
        let stub2 = ZoteroStub { _ in ZoteroResponse(status: 200, body: Data(bibB.utf8)) }
        await p.syncZotero(key: nil, transport: stub2.transport)
        #expect(b.storage.string == ZoteroLink.fileText(bibB) && !b.isDirty && b.undoManager.canUndo)
        #expect(try text(root, "refs.bib") == ZoteroLink.fileText(bibB))
        let before = try FileManager.default.attributesOfItem(atPath: root.appending(path: "refs.bib").path)[.modificationDate] as? Date
        try await Task.sleep(for: .milliseconds(20))
        await p.syncZotero(key: nil, transport: stub2.transport)
        #expect(try FileManager.default.attributesOfItem(atPath: root.appending(path: "refs.bib").path)[.modificationDate] as? Date == before)
    }

    @Test func webKeepsTheVersionAndSkipsWhenUnchanged() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "= Hi\n"])
        defer { p.disconnectZotero() }
        await p.connectZotero(ZoteroLink(source: .web, userID: "9", collection: ZoteroCollection(key: "CCC", name: "Thesis"), target: rel("refs.bib")))
        let stub = ZoteroStub { r in
            r.value(forHTTPHeaderField: "If-Modified-Since-Version") == "3"
                ? ZoteroResponse(status: 304)
                : ZoteroResponse(status: 200, headers: ["total-results": "1", "last-modified-version": "3"], body: Data(bibA.utf8))
        }
        await p.syncZotero(key: "k", transport: stub.transport)
        #expect(p.zoteroLink?.version == 3 && stub.requests[0].url!.path() == "/users/9/collections/CCC/items/top")
        await p.syncZotero(key: "k", transport: stub.transport)
        #expect(stub.requests.count == 2 && p.zoteroError == nil && p.zoteroLink?.version == 3)
        #expect(try text(root, "refs.bib") == ZoteroLink.fileText(bibA))
        // A deleted target is fetched in full again, not answered by the 304.
        try FileManager.default.removeItem(at: root.appending(path: "refs.bib"))
        await p.refreshFiles()
        await p.syncZotero(key: "k", transport: stub.transport)
        #expect(stub.requests.last?.value(forHTTPHeaderField: "If-Modified-Since-Version") == nil)
        #expect(try text(root, "refs.bib") == ZoteroLink.fileText(bibA))
    }

    @Test func badKeyAndRetryAfterAreReported() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "= Hi\n"])
        defer { p.disconnectZotero() }
        await p.connectZotero(ZoteroLink(source: .web, userID: "9", collection: nil, target: rel("refs.bib")))
        await p.syncZotero(key: "bad", transport: ZoteroStub { _ in ZoteroResponse(status: 403) }.transport)
        #expect(p.zoteroError == ZoteroError.badKey.errorDescription)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "refs.bib").path))

        let limited = ZoteroStub { _ in ZoteroResponse(status: 429, headers: ["retry-after": "120"]) }
        let t0 = Date(timeIntervalSince1970: 0)
        await p.syncZotero(key: "k", transport: limited.transport, now: t0)
        #expect(p.zoteroError == ZoteroError.rateLimited(seconds: 120).errorDescription)
        let ok = ZoteroStub { _ in ZoteroResponse(status: 200, headers: ["total-results": "1"], body: Data(bibA.utf8)) }
        await p.syncZotero(key: "k", transport: ok.transport, now: t0.addingTimeInterval(60))
        #expect(ok.requests.isEmpty)                                         // still inside Retry-After
        await p.syncZotero(key: "k", transport: ok.transport, now: t0.addingTimeInterval(121))
        #expect(ok.requests.count == 1 && p.zoteroError == nil)
    }

    @Test func linkedFileIsReadOnlyUntilDisconnected() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "refs.bib": "@misc{old, title = {Old}}\n", "other.bib": ""])
        let refs = try await p.open(rel("refs.bib")), other = try await p.open(rel("other.bib"))
        await p.connectZotero(ZoteroLink(source: .local, userID: "0", collection: nil, target: rel("refs.bib")))
        #expect(refs.isZoteroManaged && !other.isZoteroManaged)
        #expect(ZoteroLinkStore(p.id).load()?.target == rel("refs.bib"))
        await p.syncZotero(key: nil, transport: ZoteroStub { _ in ZoteroResponse(status: 200, body: Data(bibA.utf8)) }.transport)
        p.disconnectZotero()
        #expect(!refs.isZoteroManaged && p.zoteroLink == nil && ZoteroLinkStore(p.id).load() == nil)
        #expect(try text(root, "refs.bib") == ZoteroLink.fileText(bibA))      // the file stays as plain BibTeX
    }

    @Test func dirtyTargetIsNotOverwritten() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "refs.bib": "@misc{old, title = {Old}}\n"])
        defer { p.disconnectZotero() }
        p.zoteroLink = ZoteroLink(source: .local, userID: "0", collection: nil, target: rel("refs.bib"))
        let b = try await p.open(rel("refs.bib"))
        type(b, "% mine\n", at: 0)
        await p.syncZotero(key: nil, transport: ZoteroStub { _ in ZoteroResponse(status: 200, body: Data(bibA.utf8)) }.transport)
        #expect(p.zoteroError == ZoteroError.unsavedChanges("refs.bib").errorDescription)
        #expect(try text(root, "refs.bib") == "@misc{old, title = {Old}}\n" && b.storage.string.hasPrefix("% mine"))
    }
}
