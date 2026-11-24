import Foundation
import Testing
@testable import TypoAssistant

@Test func workflowParsesFrontmatterAndArgumentHint() {
    let w = Workflow.parse("---\nname: check\ndescription: \"Fix it: now\"\nargument-hint: \"[range]\"\n---\n\n# Check\n", fallbackName: "x", source: .builtIn)
    #expect(w == Workflow(name: "check", description: "Fix it: now", argumentHint: "[range]", body: "# Check\n", source: .builtIn))
    #expect(Workflow.parse("Just prose", fallbackName: "notes") == Workflow(name: "notes", description: "", body: "Just prose"))
}

@Test func workflowMarkdownRoundTrips() {
    let w = Workflow(name: "a-b", description: "Say \"hi\": now\nsecond", argumentHint: "[x]", body: "Body $ARGUMENTS")
    let back = Workflow.parse(w.markdown, fallbackName: "z")
    #expect(back.description == "Say \"hi\": now second")
    #expect(back.argumentHint == "[x]")
    #expect(back.body == "Body $ARGUMENTS\n")
}

@Test func promptSubstitutesArguments() {
    #expect(Workflow(name: "a", description: "", body: "Do $ARGUMENTS, then $ARGUMENTS.").prompt(arguments: "x") == "Do x, then x.")
    #expect(Workflow(name: "a", description: "", body: "Do it.").prompt(arguments: "x") == "Do it.\n\nARGUMENTS: x")
    #expect(Workflow(name: "a", description: "", body: "Do it.").prompt(arguments: "") == "Do it.")
}

@Test func resolveFindsWorkflows() {
    let built = Workflow(name: "check", description: "", body: "builtin", source: .builtIn)
    let mine = Workflow(name: "check", description: "", body: "mine")
    let other = Workflow(name: "mine-only", description: "", body: "m")
    func resolve(_ t: String) -> (String, String)? {
        Workflow.resolve(t, builtIns: [built], mine: [mine, other]).map { ($0.workflow.body, $0.arguments) }
    }
    #expect(resolve("/check pages 1-3")! == ("mine", "pages 1-3"))
    #expect(resolve("/typo:check")! == ("builtin", ""))
    #expect(resolve("/my:check  x ")! == ("mine", "x"))
    #expect(resolve("/mine-only")! == ("m", ""))
    #expect(Workflow.resolve("/check", builtIns: [built], mine: [])?.workflow.body == "builtin")
    #expect(resolve("/typo:mine-only") == nil)
    #expect(resolve("/unknown") == nil)
    #expect(resolve("check") == nil)
    #expect(resolve("/") == nil)
}

@Test func workflowFolderSavesListsAndRenames() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "wf-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: dir) }
    let folder = WorkflowFolder(url: dir, source: .mine)
    #expect(folder.list().isEmpty)
    try folder.save(Workflow(name: "beta", description: "B", body: "b"))
    try folder.save(Workflow(name: "alpha", description: "A", body: "a"))
    try folder.save(Workflow(name: "gamma", description: "G", body: "g"), replacing: "beta")
    #expect(folder.list().map(\.name) == ["alpha", "gamma"])
    #expect(folder.list()[1].description == "G")
    #expect(Workflow.isValidName("a-b-9") && !Workflow.isValidName("A") && !Workflow.isValidName("a--b"))
    #expect(Workflow.unique("x", among: ["x", "x-2"]) == "x-3")
}
