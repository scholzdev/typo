import Testing
import JSONRPC
@testable import ACPProtocol

struct ACPCommandTests {
    @Test func readsTheAgentsCommands() {
        let v: JSONValue = .array([
            ["name": "compact", "description": "Summarize the conversation"],
            ["name": "translate", "description": "Translate a chapter", "input": ["hint": "language"]],
            ["description": "no name, skipped"],
        ])
        let c = ACPCommand.list(v)
        #expect(c.map(\.name) == ["compact", "translate"])
        #expect(c[1].hint == "language" && c[0].hint == nil)
        #expect(ACPCommand.list(nil).isEmpty)
    }
}
