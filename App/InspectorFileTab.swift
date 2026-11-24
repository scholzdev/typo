import AppKit
import SwiftUI
import TypoKit
import TypstEngine

/// What the File tab shows about one file.
struct InspectorFileFacts {
    var path: String
    var symbol = "doc.text"
    var size: Int?
    var modified: Date?
    var isTypst = true
    /// Encoding, line ending and indentation as the editor holds them; nil while the file is not open.
    var encoding: String?
    var lineEnding: String?
    var indentation: String?
    var indentationSource = String(localized: "App settings")

    var name: String { (path as NSString).lastPathComponent }
}

struct InspectorFileTab: View {
    let project: Project
    let file: RelPath?
    @State private var included: [IncludeSite] = []

    var body: some View {
        if let file {
            InspectorFileBody(
                facts: facts(file),
                isMain: Binding(get: { project.main == file }, set: { if $0 { project.setMain(file) } }),
                locked: Binding(get: { project.previewLocked }, set: { project.previewLocked = $0 }),
                included: included,
                open: { project.show($0.file, range: NSRange(location: $0.offset, length: 0), flash: true) })
                .task(id: [file.raw, "\(project.fileRevision)"]) { included = await project.includers(of: file) }
        } else {
            ContentUnavailableView("No File Selected", systemImage: "doc")
        }
    }

    private func facts(_ file: RelPath) -> InspectorFileFacts {
        let attrs = try? FileManager.default.attributesOfItem(atPath: project.url(for: file).path)
        var f = InspectorFileFacts(path: file.raw, symbol: FileKind(path: file.raw).symbol ?? "doc.text",
                                   size: (attrs?[.size] as? NSNumber)?.intValue, modified: attrs?[.modificationDate] as? Date, isTypst: FileKind.isTypst(file.raw))
        if let b = project.openBuffer(file) {
            let format = b.diskFormat, indent = b.indentSettings
            let encoding = format.encoding.rawValue == "utf8" ? "UTF-8" : format.encoding.rawValue
            f.encoding = format.bom ? String(localized: "\(encoding) with BOM") : encoding
            f.lineEnding = ["lf": String(localized: "LF (Unix)"), "crlf": String(localized: "CRLF (Windows)"), "cr": String(localized: "CR (classic Mac)")][format.lineEnding.rawValue]
            f.indentation = indent.useTabs ? String(localized: "Tabs, width \(indent.tabWidth)") : String(localized: "\(indent.indentWidth) spaces")
            f.indentationSource = indent.preferEditorConfig ? String(localized: ".editorconfig, else app settings") : String(localized: "App settings")
        }
        return f
    }
}

struct InspectorFileBody: View {
    let facts: InspectorFileFacts
    @Binding var isMain: Bool
    @Binding var locked: Bool
    var included: [IncludeSite] = []
    var open: (IncludeSite) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
    }

    @ViewBuilder private var content: some View {
        InspectorSection("Identity") {
            HStack(spacing: 8) {
                Image(systemName: facts.symbol).font(.title2).foregroundStyle(.secondary).accessibilityHidden(true)
                Text(facts.name).font(.title3.weight(.semibold)).textSelection(.enabled)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(facts.path).font(.callout).foregroundStyle(.secondary).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                Button("Copy Path", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(facts.path, forType: .string)
                }
                .labelStyle(.iconOnly).buttonStyle(.borderless).help("Copy the project-relative path")
            }
            if let size = facts.size { InspectorRow("Size", size.formatted(.byteCount(style: .file))) }
            if let date = facts.modified { InspectorRow("Modified", date.formatted(date: .abbreviated, time: .shortened)) }
        }
        if facts.isTypst {
            InspectorSection("Document") {
                Toggle("Main document", isOn: $isMain).disabled(isMain).help("Compile and preview this file")
                Toggle("Lock preview", isOn: $locked).help("Keep the preview on the main document while another file is open")
            }
            InspectorSection("Included From") {
                if included.isEmpty {
                    Text("No other file includes or imports this one.").font(.callout).foregroundStyle(.secondary)
                }
                ForEach(included, id: \.self) { site in
                    Button(site.file.raw, systemImage: "arrow.turn.down.right") { open(site) }
                        .buttonStyle(.link).help("Show the include in \(site.file.raw)").accessibilityLabel("Included from \(site.file.raw)")
                }
            }
        }
        InspectorSection("Text") {
            if let e = facts.encoding, let l = facts.lineEnding, let i = facts.indentation {
                InspectorRow("Encoding", e)
                InspectorRow("Line endings", l)
                InspectorRow("Indentation", i)
                Text("Indentation comes from \(facts.indentationSource); change it there. Encoding and line endings are kept as the file has them.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Open the file to see its encoding, line endings and indentation.").font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

#Preview("File") {
    @Previewable @State var main = false
    @Previewable @State var locked = true
    ScrollView {
        InspectorFileBody(
            facts: InspectorFileFacts(path: "chapters/intro.typ", size: 12_345, modified: .now, encoding: "UTF-8", lineEnding: "LF (Unix)", indentation: "2 spaces", indentationSource: ".editorconfig"),
            isMain: $main, locked: $locked, included: [IncludeSite(file: RelPath("main.typ")!, offset: 120)])
            .padding(12)
    }
    .frame(width: 280, height: 560)
}
