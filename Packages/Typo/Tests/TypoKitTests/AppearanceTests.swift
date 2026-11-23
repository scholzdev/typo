import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine
#if canImport(AppKit)
import AppKit

@Suite @MainActor struct AppearanceTests {
    private func resolved(_ c: PlatformColor, dark: Bool) -> NSColor {
        var out = c
        NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance { out = c.usingColorSpace(.sRGB)! }
        return out
    }

    private func role(_ key: String) -> EditorTheme.ColorRole { EditorTheme.roles.first { $0.key == key }! }

    @Test func overridesRoundTripThroughJSON() throws {
        let o = ThemeOverrides(colors: ["keyword": "FF000080", "background": "102030FF"])
        let back = try JSONDecoder().decode(ThemeOverrides.self, from: JSONEncoder().encode(o))
        #expect(back == o)
        #expect(PlatformColor.hex(string: "FF000080")!.hexString == "FF000080")
        #expect(PlatformColor.hex(string: "#1020FF")!.hexString == "1020FFFF")
        #expect(PlatformColor.hex(string: "nope") == nil)
    }

    @Test func anOverrideChangesExactlyThatRoleInThatAppearance() {
        for base in EditorTheme.all {
            let t = base.applying(light: ThemeOverrides(), dark: ThemeOverrides(colors: ["keyword": "123456FF"]))
            for r in EditorTheme.roles {
                for dark in [false, true] {
                    let changed = r.key == "keyword" && (dark || base.isDarkOnly)
                    let before = resolved(base.color(r), dark: dark), after = resolved(t.color(r), dark: dark)
                    if changed { #expect(after.hexString == "123456FF", "\(base.id) \(r.key)") } else { #expect(after == before, "\(base.id) \(r.key) dark=\(dark)") }
                }
            }
            #expect(resolved(t.syntax[.keyword]!.color, dark: true).hexString == "123456FF")
            #expect(t.darkOverrides.colors["keyword"] == "123456FF")
        }
    }

    @Test func restoringDefaultsEqualsTheBuiltInTheme() {
        for base in EditorTheme.all {
            let custom = base.applying(light: ThemeOverrides(colors: ["text": "FF0000FF"]), dark: ThemeOverrides(colors: ["cursor": "00FF00FF"]))
            let restored = custom.applying(light: ThemeOverrides(), dark: ThemeOverrides())
            for r in EditorTheme.roles {
                for dark in [false, true] { #expect(resolved(restored.color(r), dark: dark) == resolved(base.color(r), dark: dark), "\(base.id) \(r.key)") }
                #expect(restored.builtIn(r, dark: true) === base.builtIn(r, dark: true))
            }
        }
        // Unoverridden system colors keep their identity, so the default theme still is the system's.
        #expect(EditorTheme.named("default").applying(light: ThemeOverrides(colors: ["keyword": "FF0000FF"]), dark: ThemeOverrides()).colors.text == .textColor)
    }

    @Test func theNewRolesDefaultToTodaysFixedColors() {
        let c = EditorTheme.named("default").colors
        #expect(c.cursor == .textInsertionPointColor && c.gitAdded == .systemGreen && c.gitModified == .systemBlue && c.gitDeleted == .systemRed)
        #expect(Set(EditorTheme.roles.map(\.key)).count == EditorTheme.roles.count)
        #expect(Set(EditorTheme.roles.map(\.section)) == Set(EditorTheme.sections))
        #expect(EditorTheme.roles.filter { $0.section == "Text" }.count == 11)
    }

    @Test func everySyntaxTagHasARow() {
        #expect(EditorTheme.tags.map(\.tag).sorted { $0.rawValue < $1.rawValue } == SyntaxTag.allCases)
        #expect(EditorTheme.tags.filter { $0.color == nil }.map(\.tag) == [.todo, .unit])
        for t in EditorTheme.all { #expect(Set(t.syntax.keys) == Set(SyntaxTag.allCases)) }
    }

    @Test func fontStyleDefaultsAreTodaysTable() {
        let styled = Dictionary(uniqueKeysWithValues: EditorTheme.tags.filter { $0.font != .regular }.map { ($0.tag, $0.font) })
        #expect(styled == [.strong: .bold, .heading: .bold, .listTerm: .bold, .todo: .bold, .emph: .italic])
    }

    /// Changes the shared style and puts it back with no suspension in between, so no other test sees it.
    @Test func configureReportsAChangeWhenOnlyOverridesOrFontsChange() {
        let (theme, size) = (Highlighter.style, Highlighter.fontSize)
        let custom = theme.applying(light: ThemeOverrides(colors: ["keyword": "FF0000FF"]), dark: ThemeOverrides(colors: ["keyword": "FF0000FF"]))
        let before = Highlighter.revision
        #expect(Highlighter.configure(custom, fontSize: size))
        #expect(!Highlighter.configure(custom, fontSize: size))
        #expect(resolved(Highlighter.theme[.keyword]!.color, dark: false).hexString == "FF0000FF")
        #expect(Highlighter.configure(custom, fontSize: size, styles: [.keyword: .boldItalic]))
        let keyword = Highlighter.theme[.keyword]
        #expect(Highlighter.configure(custom, fontSize: size, family: "Menlo"))
        let menlo = Highlighter.baseFont.familyName
        #expect(Highlighter.configure(theme, fontSize: size))
        #expect(Highlighter.revision == before + 4)
        #expect(keyword?.bold == true && keyword?.italic == true)
        #expect(menlo == "Menlo")
        #expect(Highlighter.theme[.keyword]?.bold == false)
    }

    @Test func facesUseRealItalicsAndFallBack() {
        let menlo = Highlighter.face(.boldItalic, size: 13, family: "Menlo")
        #expect(!menlo.oblique && menlo.font.fontDescriptor.symbolicTraits.contains([.bold, .italic]))
        let unknown = Highlighter.face(.bold, size: 13, family: "No Such Family")
        #expect(unknown.font == .monospacedSystemFont(ofSize: 13, weight: .bold))
    }

    @Test func detachedHighlightPaintsLikeTheEditor() async throws {
        let sample = "= Title\n*strong* _emph_ <lbl> @lbl\n$x^2$ #f(\"s\", 2cm) // TODO c\n```\nraw\n```\n"
        let (p, _) = try await TestEnv.project(files: ["main.typ": sample])
        let b = try await p.open(RelPath("main.typ")!)
        let detached = Highlighter.highlighted(sample)
        #expect(detached.string == sample)
        for i in 0..<detached.length {
            #expect(detached.attribute(.foregroundColor, at: i, effectiveRange: nil) as? NSColor == b.storage.attribute(.foregroundColor, at: i, effectiveRange: nil) as? NSColor, "\(i)")
            #expect(detached.attribute(.font, at: i, effectiveRange: nil) as? NSFont == b.storage.attribute(.font, at: i, effectiveRange: nil) as? NSFont, "\(i)")
        }
        let keyword = (sample as NSString).range(of: "TODO").location
        #expect(detached.attribute(.foregroundColor, at: keyword, effectiveRange: nil) as? NSColor == .systemOrange)
    }
}
#endif
