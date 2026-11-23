import Testing
import JSONRPC
@testable import ACPProtocol

struct ACPSessionOptionsTests {
    @Test func readsModesAndTheOlderModels() {
        let o = ACPSessionOptions.parse([
            "sessionId": "s",
            "modes": ["currentModeId": "default", "availableModes": [["id": "default", "name": "Default", "description": "Asks first"], ["id": "plan", "name": "Plan"]]],
            "models": ["currentModelId": "opus", "availableModels": [["modelId": "opus", "name": "Opus"], ["modelId": "haiku", "name": "Haiku"]]],
        ])
        #expect(o.modes?.choices.map(\.id) == ["default", "plan"])
        #expect(o.modes?.choices.first?.description == "Asks first")
        #expect(o.modes?.current == "default")
        #expect(o.modes?.setter == .mode)
        #expect(o.models?.choices.map(\.name) == ["Opus", "Haiku"])
        #expect(o.models?.request("haiku", session: "s").method == "session/set_model")
    }

    @Test func configOptionsWinAndGroupsAreFlattened() {
        let o = ACPSessionOptions.parse([
            "modes": ["currentModeId": "a", "availableModes": [["id": "a", "name": "A"]]],
            "configOptions": [
                ["id": "model", "name": "Model", "category": "model", "type": "select", "currentValue": "m2",
                 "options": [["group": "g", "name": "Fast", "options": [["value": "m1", "name": "M1"]]], ["group": "h", "name": "Smart", "options": [["value": "m2", "name": "M2"]]]]],
                ["id": "mode", "name": "Mode", "category": "mode", "type": "select", "currentValue": "x", "options": [["value": "x", "name": "X"]]],
                ["id": "think", "name": "Think", "type": "boolean", "currentValue": true],
            ],
        ])
        #expect(o.models?.choices.map(\.id) == ["m1", "m2"])
        #expect(o.models?.current == "m2")
        #expect(o.modes?.choices.map(\.id) == ["x"])
        let r = o.models!.request("m1", session: "s")
        #expect(r.method == "session/set_config_option")
        #expect(r.params["configId"]?.string == "model")
        #expect(r.params["value"]?.string == "m1")
    }

    @Test func followsModeUpdates() {
        var o = ACPSessionOptions.parse(["modes": ["currentModeId": "a", "availableModes": [["id": "a", "name": "A"], ["id": "b", "name": "B"]]]])
        let changed = o.apply(update: ["sessionUpdate": "current_mode_update", "currentModeId": "b"])
        #expect(changed)
        #expect(o.modes?.current == "b")
        let other = o.apply(update: ["sessionUpdate": "agent_message_chunk"])
        #expect(!other)
    }
}
