import AppKit
import CoreText
import SwiftUI
import TypoKit
import TypstEngine

/// Where the library's Fonts tab gets its families: CoreText's faces, checked against the names Typst itself lists.
enum FontScanner {
    /// Every face the system lists. Cached: the engine's font book is loaded once per process too.
    private static let systemFaces: [FontFace] = faces(of: CTFontCollectionCreateMatchingFontDescriptors(CTFontCollectionCreateFromAvailableFonts(nil)) as? [CTFontDescriptor] ?? [], source: .system)

    static func faces(of descriptors: [CTFontDescriptor], source: FontSource) -> [FontFace] {
        descriptors.compactMap { d in
            guard let family = CTFontDescriptorCopyAttribute(d, kCTFontFamilyNameAttribute) as? String, !family.hasPrefix(".") else { return nil }
            let traits = CTFontDescriptorCopyAttribute(d, kCTFontTraitsAttribute) as? [CFString: Any] ?? [:]
            let symbolic = (traits[kCTFontSymbolicTrait] as? NSNumber)?.uint32Value ?? 0
            return FontFace(family: family, style: CTFontDescriptorCopyAttribute(d, kCTFontStyleNameAttribute) as? String ?? "Regular",
                            weight: FontFace.weight(fromTrait: (traits[kCTFontWeightTrait] as? NSNumber)?.doubleValue ?? 0),
                            italic: symbolic & CTFontSymbolicTraits.traitItalic.rawValue != 0,
                            monospaced: symbolic & CTFontSymbolicTraits.traitMonoSpace.rawValue != 0,
                            design: FontFace.design(fromClass: Int(symbolic >> 28)), source: source)
        }
    }

    /// The Typst-visible system families, plus the project's font files.
    @MainActor static func load(project: Project) async -> (families: [FontFamily], projectDescriptors: [String: CTFontDescriptor]) {
        // The engine's font names: any Typst file will do as the stand-in the completion runs in.
        let host = project.selectedFile.flatMap { FileKind(path: $0.raw) == .typst ? $0 : nil } ?? project.allFiles.first { FileKind(path: $0.raw) == .typst }
        var typstNames: [String] = []
        if let host { typstNames = await project.fontFamilyNames(host: host) }
        let system = FontCatalog.reconcile(system: FontCatalog.group(systemFaces), typstNames: typstNames)

        var descriptors: [String: CTFontDescriptor] = [:]
        var projectFaces: [FontFace] = []
        for path in project.allFiles where FileKind(path: path.raw) == .font {
            let found = CTFontManagerCreateFontDescriptorsFromURL(project.url(for: path) as CFURL) as? [CTFontDescriptor] ?? []
            for d in found { if let f = CTFontDescriptorCopyAttribute(d, kCTFontFamilyNameAttribute) as? String { descriptors[f] = d } }
            projectFaces += faces(of: found, source: .project)
        }
        return (FontCatalog.merge(project: FontCatalog.group(projectFaces), system: system), descriptors)
    }
}

extension EditorView.Coordinator {
    /// Puts `names` at the caret: into the `font:` value there, else as a `#set text(font: …)` rule.
    func insertFonts(_ names: [String]) {
        guard let tv = textView, let r = FontCatalog.insertion(of: names, in: tv.string, caret: tv.selectedRange().location) else { return }
        replace(r.range, with: r.text, selecting: NSRange(location: r.range.location + (r.text as NSString).length, length: 0))
    }
}

/// A family name set in its own face; a project font that is not installed is built from its file's descriptor.
func fontSwiftUI(_ family: FontFamily, descriptors: [String: CTFontDescriptor], size: CGFloat) -> Font {
    if family.source == .project, let d = descriptors[family.name] { return Font(CTFontCreateWithFontDescriptor(d, size, nil)) }
    return Font(NSFont(descriptor: NSFontDescriptor(fontAttributes: [.family: family.name]), size: size) ?? .systemFont(ofSize: size))
}

/// The Fonts tab's detail pane: sample, style chips, the code line and the fallback list.
struct FontDetail: View {
    let family: FontFamily
    let descriptors: [String: CTFontDescriptor]
    @Binding var sample: String
    let picks: [String]
    let names: [String]
    let togglePick: () -> Void
    let insertBar: AnyView

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(sample.isEmpty ? "The quick brown fox" : sample).font(fontSwiftUI(family, descriptors: descriptors, size: 28)).lineLimit(2).minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            TextField("Sample Text", text: $sample).textFieldStyle(.roundedBorder)
            Text(family.name).font(.system(size: 17, weight: .bold))
            Text(sourceNote).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            // Weights as the chips the row shows, then every style spelled out.
            FlowChips(chips: family.weights.map { FontCatalog.weightName($0) } + (family.hasItalic ? ["Italic"] : []) + (family.isMonospaced ? ["Mono"] : []))
            Text("Styles: " + family.faces.map(\.style).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            Text(FontCatalog.setRule(names)).font(.system(.callout, design: .monospaced)).textSelection(.enabled).padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
            HStack {
                Button(picks.contains(family.name) ? "Remove from List" : "Add to Fallback List", action: togglePick).buttonStyle(.glass)
                    .help("⌘-click a row does the same; several fonts become a fallback list")
                Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(FontCatalog.setRule(names), forType: .string) }.buttonStyle(.glass)
            }
            Spacer()
            insertBar
        }
    }

    private var sourceNote: String {
        switch family.source {
        case .builtin: "Built into Typst: available on every machine."
        case .project: "A font file in this project: it travels with the project and wins over an installed font of the same name."
        case .system: "Installed on this Mac, so exports on other machines may substitute it."
        }
    }
}

private struct FlowChips: View {
    let chips: [String]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 4, alignment: .leading)], alignment: .leading, spacing: 4) {
            ForEach(chips, id: \.self) { c in
                Text(c).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .overlay(Capsule().stroke(Color.secondary.opacity(0.5), lineWidth: 1))
            }
        }
    }
}
