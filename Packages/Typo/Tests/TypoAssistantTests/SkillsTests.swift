import Foundation
import Testing
@testable import TypoAssistant

private func tempDir() -> URL {
    let u = FileManager.default.temporaryDirectory.appending(path: "skills-\(UUID().uuidString)", directoryHint: .isDirectory)
    try! FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

@Test func skillParsesFrontmatterAndBody() {
    let s = Skill.parse("---\nname: math\ndescription: Write math. Use when: formulas\n---\n\n# Math\n\n- Inline\n", fallbackName: "x")
    #expect(s == Skill(name: "math", description: "Write math. Use when: formulas", body: "# Math\n\n- Inline\n"))
}

@Test func skillParsesQuotedValuesAndCRLF() {
    let s = Skill.parse("---\r\nname: 'a'\r\ndescription: \"Say \\\"hi\\\": now\"\r\n---\r\nBody", fallbackName: "x")
    #expect(s.name == "a")
    #expect(s.description == "Say \"hi\": now")
    #expect(s.body == "Body")
}

@Test func skillWithoutFrontmatterIsAllBody() {
    #expect(Skill.parse("Just prose.\n", fallbackName: "notes") == Skill(name: "notes", description: "", body: "Just prose.\n"))
    // An unclosed block is not frontmatter.
    #expect(Skill.parse("---\nname: a\nno end", fallbackName: "f").name == "f")
    #expect(Skill.parse("---\nname: a\n---", fallbackName: "f") == Skill(name: "a", description: "", body: ""))
}

@Test func pluginListsAndAssembles() throws {
    let root = tempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let plugin = SkillPlugin(url: root.appending(path: "user"), name: "typo-user")
    #expect(plugin.list().isEmpty)
    for (name, d) in [("alpha", "A"), ("gamma", "G")] {
        try FileManager.default.createDirectory(at: plugin.folder(name), withIntermediateDirectories: true)
        try Data("---\nname: \(name)\ndescription: \(d)\n---\nbody".utf8).write(to: plugin.folder(name).appending(path: "SKILL.md"))
    }
    #expect(plugin.list().map(\.name) == ["alpha", "gamma"])
    #expect(plugin.list()[1].description == "G")

    let dest = root.appending(path: "cache/typo-user")
    try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
    #expect(try plugin.assemble(into: dest, enabled: ["typo-user/gamma"]) == dest)
    #expect(SkillPlugin(url: dest, name: "typo-user").list().map(\.name) == ["gamma"])
    #expect(FileManager.default.fileExists(atPath: dest.appending(path: ".claude-plugin/plugin.json").path))
    // Again, with a different set: the folder is replaced, not merged.
    _ = try plugin.assemble(into: dest, enabled: ["typo-user/alpha"])
    #expect(SkillPlugin(url: dest, name: "typo-user").list().map(\.name) == ["alpha"])
    #expect(try plugin.assemble(into: dest, enabled: []) == nil)
    #expect(!FileManager.default.fileExists(atPath: dest.path))
    #expect(try FileManager.default.contentsOfDirectory(atPath: dest.deletingLastPathComponent().path).isEmpty)
}

@Test func assemblyWritesAManifestWhenTheSourceHasNone() throws {
    let root = tempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let src = root.appending(path: "src")
    try FileManager.default.createDirectory(at: src.appending(path: "skills/one"), withIntermediateDirectories: true)
    try Data("Prose only".utf8).write(to: src.appending(path: "skills/one/SKILL.md"))
    let dest = try SkillPlugin(url: src, name: "typo").assemble(into: root.appending(path: "out"), enabled: ["typo/one"])
    #expect(dest != nil)
    let manifest = try String(contentsOf: root.appending(path: "out/.claude-plugin/plugin.json"), encoding: .utf8)
    #expect(manifest.contains("\"typo\""))
    #expect(SkillPlugin(url: root.appending(path: "out"), name: "typo").list() == [Skill(name: "one", description: "", body: "Prose only")])
}

