import Testing
import Foundation
import TypoTestSupport
@testable import TypoKit

struct TextLanguageTests {
    func lang(_ marked: String, inherited: TextLanguage? = nil) -> String? {
        let text = marked.replacingOccurrences(of: "|", with: "")
        let caret = (marked as NSString).range(of: "|").location
        return TextLanguage.at(caret, in: text, inherited: inherited)?.identifier
    }

    @Test func setApplies() { #expect(lang("#set text(lang: \"de\")\nHal|lo") == "de") }
    @Test func beforeSetNone() { #expect(lang("Hal|lo\n#set text(lang: \"de\")") == nil) }
    @Test func region() { #expect(lang("#set text(font: \"X\", lang: \"de\", region: \"CH\")\n|a") == "de_CH") }
    @Test func laterSetSwitches() { #expect(lang("#set text(lang: \"de\")\na\n#set text(lang: \"en\")\n|b") == "en") }
    @Test func textCallScoped() {
        #expect(lang("#set text(lang: \"de\")\n#text(lang: \"fr\")[bon|jour] x") == "fr")
        #expect(lang("#set text(lang: \"de\")\n#text(lang: \"fr\")[bonjour] |x") == "de")
    }
    @Test func commentIgnored() { #expect(lang("// #set text(lang: \"de\")\n|a") == nil) }
    @Test func blockCommentIgnored() { #expect(lang("/* #set text(lang: \"de\") */ |a") == nil) }
    @Test func stringIgnored() { #expect(lang("#let s = \"#set text(lang: \\\"de\\\")\"\n|a") == nil) }
    @Test func otherCallIgnored() { #expect(lang("#set par(lang: \"de\")\n|a") == nil) }
    @Test func inheritedFromMain() {
        #expect(lang("|a", inherited: TextLanguage(lang: "de", region: nil)) == "de")
        #expect(lang("#set text(lang: \"en\")\n|a", inherited: TextLanguage(lang: "de", region: nil)) == "en")
    }
    @Test func documentDefault() {
        #expect(TextLanguage.documentDefault(in: "x\n#set text(lang: \"de\", region: \"AT\")\n")?.identifier == "de_AT")
        #expect(TextLanguage.documentDefault(in: "x") == nil)
    }
}
