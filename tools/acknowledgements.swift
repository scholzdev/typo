import Foundation

// Writes App/Acknowledgements.txt from the bridge's Cargo dependency graph and the license texts in the local Cargo registry.
// Run from the repo root: swift tools/acknowledgements.swift
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func cargoMetadata() -> [String: Any] {
    for extra in [["--offline"], []] {   // offline first; the registry cache is normally present after a bridge build
        let p = Process(), out = Pipe()
        p.executableURL = URL(filePath: "/usr/bin/env")
        p.arguments = ["cargo", "metadata", "--format-version", "1", "--locked"] + extra + ["--manifest-path", "bridge/Cargo.toml"]
        p.standardOutput = out; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { continue }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        if p.terminationStatus == 0, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return json }
    }
    fail("cargo metadata failed")
}

let meta = cargoMetadata()
guard let all = meta["packages"] as? [[String: Any]] else { fail("no packages in metadata") }
// `packages` holds only the resolved graph; the bridge's own crate is not a dependency to credit.
let deps = all.filter { ($0["name"] as? String) != "typst-bridge" }
    .sorted { ($0["name"] as! String, $0["version"] as! String) < ($1["name"] as! String, $1["version"] as! String) }

func crateDir(_ name: String) -> URL {
    guard let m = deps.first(where: { $0["name"] as? String == name })?["manifest_path"] as? String else { fail("crate \(name) not in the graph") }
    return URL(filePath: m).deletingLastPathComponent()
}

func read(_ url: URL) -> String {
    guard let s = try? String(contentsOf: url, encoding: .utf8) else { fail("cannot read \(url.path)") }
    return s
}

let assets = crateDir("typst-assets")
// typst-assets ships the Apache-2.0 text, the font licenses (NOTICE) for its embedded fonts; aho-corasick's MIT text stands for the MIT crates.
let apache = read(assets.appending(path: "LICENSE"))
let fontNotice = read(assets.appending(path: "NOTICE"))
let mit = read(crateDir("aho-corasick").appending(path: "LICENSE-MIT"))

var out = """
Typo is built on Typst and a number of open-source Rust libraries. Thank you to all their authors.

The libraries in the typesetting engine's dependency graph, with the license each declares:


"""
for d in deps {
    out += "\(d["name"] as! String) \(d["version"] as! String) — \((d["license"] as? String) ?? "see crate")\n"
}
let rule = String(repeating: "=", count: 80)
// Sparkle is a Swift package; ./build.sh checks it out next to the build.
let sparkleCheckout = "build/DerivedData/SourcePackages/checkouts/Sparkle"
guard let sparkle = try? String(contentsOfFile: "\(sparkleCheckout)/LICENSE", encoding: .utf8) else {
    fatalError("Sparkle's LICENSE is missing. Run ./build.sh first.")
}
let resolved = try? String(contentsOfFile: "Typo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved", encoding: .utf8)
let sparkleVersion = resolved?.firstMatch(of: #/"sparkle"[\s\S]*?"version" : "([^"]+)"/#).map { String($0.1) } ?? ""
out += """


\(rule)
Apache License 2.0 (text as shipped with typst-assets)
\(rule)

\(apache)

\(rule)
MIT License (text as shipped with aho-corasick; every MIT crate above carries its own copyright line)
\(rule)

\(mit)

\(rule)
Fonts and other assets bundled with Typst (NOTICE as shipped with typst-assets)
\(rule)

\(fontNotice)

\(rule)
Sparkle \(sparkleVersion), software updates (MIT License)
\(rule)

\(sparkle)
"""
try out.write(toFile: "App/Acknowledgements.txt", atomically: true, encoding: .utf8)
print("wrote App/Acknowledgements.txt with \(deps.count) packages")
