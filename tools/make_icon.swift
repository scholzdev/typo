import AppKit

// Writes App/AppIcon.icon, an Icon Composer bundle for Typo: an indigo fill, a white "Card" glass group, and above it
// the word "Ty" set in Libertinus Serif Bold (Typst's default font, OFL, tools/fonts) with a caret, plus a red
// spell-check squiggle in its own group so the glass gives it depth.
// Run: swift tools/make_icon.swift App/AppIcon.icon
// Preview: ictool App/AppIcon.icon --export-image --output-file icon.png --platform macOS --rendition Default
//          --width 512 --height 512 --scale 1
let out = URL(fileURLWithPath: CommandLine.arguments[1])
let assets = out.appending(path: "Assets")
try? FileManager.default.removeItem(at: assets)
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

let canvas: CGFloat = 1024
let ink = NSColor(srgbRed: 0.12, green: 0.10, blue: 0.30, alpha: 1)
let indigo = NSColor(srgbRed: 0.38, green: 0.36, blue: 0.95, alpha: 1)
let red = NSColor(srgbRed: 0.95, green: 0.22, blue: 0.27, alpha: 1)

let fontURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "fonts/LibertinusSerif-Bold.otf")
let provider = CGDataProvider(url: fontURL as CFURL)!
let font = CTFontCreateWithGraphicsFont(CGFont(provider)!, 330, nil, nil)

/// Each layer is a full canvas, origin at the centre, y up.
func layer(_ name: String, _ draw: (CGContext) -> Void) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    cg.translateBy(x: canvas / 2, y: canvas / 2)
    draw(cg)
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: assets.appending(path: name))
}

// "Ty" as one path, kerned by the font, then centred on its ink bounds.
let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Ty", attributes: [.init(kCTFontAttributeName as String): font]))
let word = CGMutablePath()
for run in CTLineGetGlyphRuns(line) as! [CTRun] {
    let n = CTRunGetGlyphCount(run)
    var glyphs = [CGGlyph](repeating: 0, count: n), pos = [CGPoint](repeating: .zero, count: n)
    CTRunGetGlyphs(run, CFRange(), &glyphs); CTRunGetPositions(run, CFRange(), &pos)
    for i in 0..<n { if let p = CTFontCreatePathForGlyph(font, glyphs[i], nil) { word.addPath(p, transform: CGAffineTransform(translationX: pos[i].x, y: pos[i].y)) } }
}
let wb = word.boundingBoxOfPath
let wordCentre = CGPoint(x: -20, y: 30)   // nudged left to leave room for the caret
let placed = CGMutablePath()
placed.addPath(word, transform: CGAffineTransform(translationX: wordCentre.x - wb.midX, y: wordCentre.y - wb.midY))
let pb = placed.boundingBoxOfPath

let card = CGRect(x: -300, y: -230, width: 600, height: 470)

try layer("card.png") { cg in
    cg.addPath(CGPath(roundedRect: card, cornerWidth: 64, cornerHeight: 64, transform: nil))
    cg.setFillColor(NSColor(white: 0.99, alpha: 1).cgColor)
    cg.fillPath()
}

try layer("word.png") { cg in
    cg.addPath(placed)
    cg.setFillColor(ink.cgColor)
    cg.fillPath()
    // the caret, right after the word
    cg.addPath(CGPath(roundedRect: CGRect(x: pb.maxX + 26, y: pb.minY + 10, width: 16, height: pb.height + 10), cornerWidth: 8, cornerHeight: 8, transform: nil))
    cg.setFillColor(indigo.cgColor)
    cg.fillPath()
}

try layer("squiggle.png") { cg in
    let p = CGMutablePath(), y = pb.minY - 52, amp: CGFloat = 13, step: CGFloat = 30
    var x = pb.minX - 6, up = true
    p.move(to: CGPoint(x: x, y: y))
    while x < pb.maxX + 8 { x += step; p.addLine(to: CGPoint(x: x, y: up ? y + amp * 2 : y)); up.toggle() }
    cg.addPath(p)
    cg.setStrokeColor(red.cgColor)
    cg.setLineWidth(16); cg.setLineCap(.round); cg.setLineJoin(.round)
    cg.strokePath()
}

let json = """
{
  "fill" : {
    "linear-gradient" : [
      "srgb:0.40000,0.38000,0.96000,1.00000",
      "srgb:0.16000,0.11000,0.46000,1.00000"
    ]
  },
  "groups" : [
    {
      "layers" : [
        { "image-name" : "squiggle.png", "name" : "squiggle" }
      ],
      "name" : "Squiggle",
      "shadow" : { "kind" : "layer-color", "opacity" : 0.5 },
      "specular" : true,
      "translucency" : { "enabled" : false, "value" : 0.5 }
    },
    {
      "layers" : [
        { "image-name" : "word.png", "name" : "word" }
      ],
      "name" : "Word",
      "shadow" : { "kind" : "none", "opacity" : 0 },
      "specular" : false,
      "translucency" : { "enabled" : false, "value" : 0.5 }
    },
    {
      "layers" : [
        { "image-name" : "card.png", "name" : "card" }
      ],
      "name" : "Card",
      "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
      "specular" : true,
      "translucency" : { "enabled" : false, "value" : 0.5 }
    }
  ],
  "supported-platforms" : {
    "squares" : "shared"
  }
}
"""
try json.write(to: out.appending(path: "icon.json"), atomically: true, encoding: .utf8)
print("wrote \(out.path)")
