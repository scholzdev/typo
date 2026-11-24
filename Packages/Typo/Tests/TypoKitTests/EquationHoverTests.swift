import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine


@Suite(.serialized) @MainActor struct EquationHoverTests {
    static let main = RelPath("main.typ")!

    /// Hover at the first `needle` (+ `shift`) of a compiled project.
    static func hover(_ text: String, _ needle: String, shift: Int = 1) async throws -> (HoverInfo?, Project, Buffer) {
        let (p, _) = try await TestEnv.project(files: ["main.typ": text])
        let b = try await p.open(main)
        _ = await p.settle()
        let at = (text as NSString).range(of: needle).location + shift
        return (await p.hover(in: main, at: at), p, b)
    }

    static func save(_ e: EquationImage?, _ name: String) {
        guard let outDir = ProcessInfo.processInfo.environment["EQUATION_HOVER_PNG_DIR"], let e else { return }
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        guard let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: "\(outDir)/\(name).png") as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, e.image, nil)
        CGImageDestinationFinalize(dest)
    }

    @Test func inlineEquation() async throws {
        let text = "Value $a + x^2 = c$ here."
        let (info, _, _) = try await Self.hover(text, "x^2")
        let i = try #require(info)
        let e = try #require(i.equation)
        Self.save(e, "inline")
        #expect(e.size.width > e.size.height && e.size.height > 6 && e.size.width < 100, "\(e.size)")
        #expect(e.size.height > 6 && e.size.width < 100)
        #expect(e.image.width > Int(e.size.width))
        #expect(i.range == (text as NSString).range(of: "$a + x^2 = c$"))
    }

    @Test func numberedBlockEquation() async throws {
        let text = "#set math.equation(numbering: \"(1)\")\n$ integral_0^1 x^2 dif x $\n"
        let (info, _, _) = try await Self.hover(text, "integral", shift: 2)
        let e = try #require(info?.equation)
        Self.save(e, "block")
        #expect(e.size.width > 20 && e.size.height > 10)
    }

    @Test func labelledEquationRendersForCompletion() async throws {
        let text = "$ sum_(k=1)^n k = (n (n + 1)) / 2 $ <gauss>\n= Intro <intro>\n"
        let (p, _) = try await TestEnv.project(files: ["main.typ": text])
        _ = try await p.open(Self.main)
        _ = await p.settle()
        let e = try #require(await p.labelEquation("gauss", pixelsPerPoint: 2))
        Self.save(e, "label")
        #expect(e.size.width > 40 && e.size.height > 10, "\(e.size)")
        #expect(await p.labelEquation("intro", pixelsPerPoint: 2) == nil)
        #expect(await p.labelEquation("missing", pixelsPerPoint: 2) == nil)
    }

    @Test func equationHoverHasNoSymbolTooltip() async throws {
        let (info, _, _) = try await Self.hover("$ integral_0^1 x^2 dif x = 1/3 $\n", "integral", shift: 2)
        let i = try #require(info)
        #expect(i.equation != nil)
        #expect(i.tooltip == nil)
    }

    @Test func macroEquationComesFromTheDocument() async throws {
        let (info, _, _) = try await Self.hover("#let r = $RR$\n$#r^n$\n", "#r^n")
        let e = try #require(info?.equation)
        Self.save(e, "macro")
        #expect(e.size.width > 10)
    }

    /// Text glued to the formula must not leak into the padding: the outer pixel columns stay background.
    @Test(arguments: ["$a + x^2 = c$steht", "Wort$y$Wort"]) func neighbouringTextDoesNotLeak(text: String) async throws {
        let (info, _, _) = try await Self.hover(text, "$", shift: 2)
        let e = try #require(info?.equation)
        Self.save(e, text.hasPrefix("$") ? "glued" : "glued2")
        let (w, h) = (e.image.width, e.image.height)
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = try #require(CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(e.image, in: CGRect(x: 0, y: 0, width: w, height: h))
        for x in [0, 1, 2, w - 3, w - 2, w - 1] {
            for y in 0..<h { #expect(px[(y * w + x) * 4..<(y * w + x) * 4 + 3].allSatisfy { $0 == 255 }, "column \(x) row \(y)") }
        }
    }

    @Test func editedFileHasNoImage() async throws {
        let (_, p, b) = try await Self.hover("Value $x^2$ here.", "x^2")
        let gate = DispatchSemaphore(value: 0)
        Task { await p.engine.stall(gate) }
        try await Task.sleep(for: .milliseconds(100))
        replace(b, NSRange(location: 0, length: 0), with: "A ")      // outside the formula, still stale
        let t = Task { await p.hover(in: Self.main, at: 10) }
        try await Task.sleep(for: .milliseconds(100))
        gate.signal()
        #expect(await t.value?.equation == nil)
    }

    @Test func cursorOutsideMathHasNoImage() async throws {
        let (info, _, _) = try await Self.hover("Plain text $x$.", "Plain")
        #expect(info?.equation == nil)
    }

    @Test func repeatedEquationDoesNotMergeOccurrences() async throws {
        let text = "#let e = $a^2 + b^2$\n#e\n#pagebreak()\n#e\n#pagebreak()\n#e\n"
        let (info, _, _) = try await Self.hover(text, "a^2")
        let e = try #require(info?.equation)
        #expect(e.size.height < 60)         // one formula, not a column spanning the pages
    }
}
