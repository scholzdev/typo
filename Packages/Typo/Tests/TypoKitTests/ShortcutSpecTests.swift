import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit

@Suite struct ShortcutSpecTests {
    @Test func displayUsesMacOrderAndGlyphs() {
        #expect(ShortcutSpec("p", [.command, .shift]).display == "⇧⌘P")
        #expect(ShortcutSpec("j", [.command, .control]).display == "⌃⌘J")
        #expect(ShortcutSpec("+", [.command, .option]).display == "⌥⌘+")
        #expect(ShortcutSpec(.named(.leftArrow), [.command, .option]).display == "⌥⌘←")
        #expect(ShortcutSpec(.named(.return), [.command, .option, .shift, .control]).display == "⌃⌥⇧⌘↩")
        #expect(ShortcutSpec(.named(.f5)).display == "F5")
        #expect(ShortcutSpec(.named(.pageDown), [.command]).display == "⌘⇟")
    }

    @Test func codableRoundTripKeepsRemovedShortcut() throws {
        var o = ShortcutOverrides()
        o.values["File/Save"] = .some(ShortcutSpec("s", [.command, .option]))
        o.values["File/Close Tab"] = .some(nil)
        o.values["View/Fold Section"] = .some(ShortcutSpec(.named(.f3)))
        let data = try JSONEncoder().encode(o)
        #expect(String(decoding: data, as: UTF8.self).contains("null"))
        let back = try JSONDecoder().decode(ShortcutOverrides.self, from: data)
        #expect(back == o)
        #expect(back.effective("File/Close Tab", default: ShortcutSpec("w", [.command])) == nil)
        #expect(back.effective("File/Open…", default: ShortcutSpec("o", [.command])) == ShortcutSpec("o", [.command]))
    }

    @Test func validity() {
        #expect(ShortcutSpec("a", [.command]).isValid)
        #expect(ShortcutSpec("a", [.control, .option]).isValid)
        #expect(!ShortcutSpec("a").isValid)
        #expect(!ShortcutSpec("a", [.option, .shift]).isValid)
        #expect(ShortcutSpec(.named(.f7)).isValid)
        #expect(!ShortcutSpec(.named(.return)).isValid)
    }

    @Test func reservedCombinationsAreRefused() {
        #expect(ShortcutSpec("q", [.command]).refusal != nil)
        #expect(ShortcutSpec("h", [.command, .option]).refusal != nil)
        #expect(ShortcutSpec("z", [.command, .shift]).refusal != nil)
        #expect(ShortcutSpec(.named(.f5)).refusal != nil)
        #expect(ShortcutSpec(.named(.escape), [.option]).refusal != nil)
        #expect(ShortcutSpec("w", [.command]).refusal == nil)
        #expect(ShortcutSpec("a").refusal != nil)   // invalid, not reserved
    }

    @Test func conflictDetection() {
        let s = ShortcutSpec("k", [.command])
        let c = ShortcutSpec.conflicts([("a", s), ("b", s), ("c", ShortcutSpec("l", [.command]))])
        #expect(c == [s: ["a", "b"]])
        #expect(ShortcutSpec.conflicts([("a", s), ("b", s), ("c", s)])[s]?.count == 3)
        // Rebinding one of two resolves it.
        #expect(ShortcutSpec.conflicts([("a", s), ("b", ShortcutSpec("k", [.command, .shift]))]).isEmpty)
    }

    @Test func legacyJumpShortcutMigrates() {
        // ⌃⌘J as EventModifiers(.command, .control) = 16 + 4
        #expect(ShortcutSpec(legacy: "20:j") == ShortcutSpec("j", [.command, .control]))
        #expect(ShortcutSpec(legacy: "28::") == ShortcutSpec(":", [.command, .control, .option]))
        #expect(ShortcutSpec(legacy: "garbage") == nil)
    }
}

@Suite struct ShortcutSetsTests {
    private let save = ShortcutSpec("s", [.command, .option])

    @Test func legacyOverridesBecomeTheSelectedCustomSet() {
        let legacy = ShortcutOverrides(["File/Save": .some(save)])
        let s = ShortcutSets(migrating: legacy)
        #expect(s.selected == "Custom" && s.current == legacy && s.names == ["Default", "Vim", "Custom"])
        #expect(ShortcutSets(migrating: ShortcutOverrides()).isDefault)
    }

    @Test func editingDefaultCreatesCustomThenUniqueNames() {
        var s = ShortcutSets()
        s.edit { $0.values["File/Save"] = .some(save) }
        #expect(s.selected == "Custom" && s.current.values["File/Save"] == .some(save))
        s.select("Default")
        s.edit { $0.values["File/Open…"] = .some(nil) }
        #expect(s.selected == "Custom 2" && s.current.values["File/Save"] == nil)
        #expect(ShortcutSets().current.values.isEmpty)
    }

    @Test func duplicateRenameDeleteKeepNamesUnique() {
        var s = ShortcutSets(migrating: ShortcutOverrides(["File/Save": .some(save)]))
        let refused = [s.duplicate(as: "Custom"), s.duplicate(as: "Default"), s.duplicate(as: "  ")]
        #expect(refused == [false, false, false])
        let copied = s.duplicate(as: " Mine ")
        #expect(copied && s.selected == "Mine" && s.current.values["File/Save"] == .some(save))
        let clash = s.rename(to: "Custom"), renamed = s.rename(to: "Work")
        #expect(!clash && renamed && s.names == ["Default", "Vim", "Custom", "Work"])
        s.deleteCurrent()
        #expect(s.isDefault && s.names == ["Default", "Vim", "Custom"])
        let onDefault = s.rename(to: "X")
        #expect(!onDefault)
        s.select("Custom")
        s.resetCurrent()
        #expect(s.current.values.isEmpty && s.names.contains("Custom"))
    }

    @Test func vimSetIsBuiltInAndEditingCopiesIt() {
        var s = ShortcutSets()
        s.select("Vim")
        #expect(s.names == ["Default", "Vim"] && s.isBuiltIn && !s.isDefault)
        #expect(s.current.values["Format/Re-Indent"] == .some(ShortcutSpec("i", [.command, .option])))
        let refused = [s.rename(to: "X"), s.duplicate(as: "Vim")]
        s.deleteCurrent(); s.resetCurrent()
        #expect(refused == [false, false] && s.selected == "Vim" && s.current == ShortcutSets.builtIns["Vim"])
        s.edit { $0.values["File/Save"] = .some(save) }
        #expect(s.selected == "Vim Custom" && s.current.values["File/Save"] == .some(save) && s.current.values["Format/Re-Indent"] != nil)
        #expect(ShortcutSets.builtIns["Vim"]?.values["File/Save"] == nil)
    }

    @Test func codableRoundTrip() throws {
        var s = ShortcutSets()
        s.edit { $0.values["File/Save"] = .some(nil) }
        #expect(try JSONDecoder().decode(ShortcutSets.self, from: JSONEncoder().encode(s)) == s)
    }
}
