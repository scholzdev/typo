import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine
#if canImport(AppKit)
import AppKit

@Suite @MainActor struct EditorStyleTests {
    private func resolved(_ c: PlatformColor, dark: Bool) -> NSColor {
        var out = c
        NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance { out = c.usingColorSpace(.sRGB)! }
        return out
    }

    @Test func defaultThemeIsTheXcodeLikeMap() {
        let s = EditorTheme.named("default").syntax
        let expected: [SyntaxTag: NSColor] = [.comment: .secondaryLabelColor, .punctuation: .secondaryLabelColor, .escape: .systemOrange,
            .link: .systemBlue, .raw: .systemBrown, .label: .systemGreen, .ref: .systemGreen, .listMarker: .systemPink,
            .mathDelimiter: .systemTeal, .mathOperator: .systemTeal, .mathGroupingParens: .systemTeal, .keyword: .systemPink,
            .operator: .systemPink, .number: .systemPurple, .string: .systemRed, .function: .systemBlue, .interpolated: .systemIndigo,
            .error: .systemRed, .strong: .textColor, .emph: .textColor, .heading: .textColor, .listTerm: .textColor]
        for (tag, color) in expected { #expect(s[tag]?.color == color, "\(tag)") }
        #expect(s[.strong]?.bold == true && s[.heading]?.bold == true && s[.listTerm]?.bold == true && s[.emph]?.italic == true)
        #expect(s[.keyword]?.bold == false)
        #expect(s[.unit] != nil)
        #expect(EditorTheme.named("default").colors.text == .textColor)
        #expect(EditorTheme.named("no such theme").id == "default")
    }

    @Test func tabBarIsDarkerThanADarkEditorAndGreyerThanALightOne() {
        func bright(_ c: NSColor) -> CGFloat { c.brightnessComponent }
        let dracula = EditorTheme.named("dracula").colors
        #expect(bright(resolved(dracula.tabBar, dark: true)) < bright(resolved(dracula.background, dark: true)))
        let light = EditorTheme.named("default").colors
        #expect(bright(resolved(light.tabBar, dark: false)) < bright(resolved(light.background, dark: false)))
    }

    @Test func twoVariantThemesFollowTheAppearance() {
        for id in ["solarized", "github"] {
            let t = EditorTheme.named(id)
            #expect(!t.isDarkOnly)
            #expect(resolved(t.colors.background, dark: false) != resolved(t.colors.background, dark: true), "\(id)")
            #expect(resolved(t.syntax[.keyword]!.color, dark: true).alphaComponent == 1)
        }
        let dracula = EditorTheme.named("dracula")
        #expect(dracula.isDarkOnly)
        #expect(resolved(dracula.colors.background, dark: false) == resolved(dracula.colors.background, dark: true))
        #expect(resolved(EditorTheme.named("solarized").colors.background, dark: false) == NSColor(srgbRed: 0xfd / 255.0, green: 0xf6 / 255.0, blue: 0xe3 / 255.0, alpha: 1))
        #expect(Set(EditorTheme.all.map(\.name)) == ["Default", "Solarized", "GitHub", "Dracula"])
    }

    @Test func fontsFollowTheSize() {
        #expect(Highlighter.font(size: 18).pointSize == 18)
        #expect(Highlighter.font(size: 18, bold: true).fontDescriptor.symbolicTraits.contains(.bold))
    }

    /// Changes the shared style and puts it back with no suspension in between, so no other test sees it.
    @Test func restyleRepaintsOpenBuffersWithoutAnEdit() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "= Title\n#let x = 1\n"])
        let b = try await p.open(RelPath("main.typ")!)
        let undoable = b.undoManager.canUndo
        let (theme, size) = (Highlighter.style, Highlighter.fontSize)
        #expect(Highlighter.configure(EditorTheme.named("dracula"), fontSize: 20))
        #expect(!Highlighter.configure(EditorTheme.named("dracula"), fontSize: 20))
        p.restyleBuffers()
        let font = b.storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let keyword = b.storage.attribute(.foregroundColor, at: (b.storage.string as NSString).range(of: "let").location, effectiveRange: nil) as? NSColor
        let expectedKeyword = Highlighter.theme[.keyword]?.color
        _ = Highlighter.configure(theme, fontSize: size)
        p.restyleBuffers()
        #expect(font?.pointSize == 20)
        #expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)    // the heading
        #expect(keyword != nil && keyword == expectedKeyword)
        #expect((b.storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == size)
        #expect(b.undoManager.canUndo == undoable)
        #expect(!b.isDirty)
    }
}
#endif
