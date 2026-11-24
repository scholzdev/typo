import AppKit
import SwiftUI
import TypoKit
import TypstEngine

/// What the Document tab shows.
struct InspectorDocumentFacts {
    var pages = 0
    var words = 0
    var facts = DocumentFacts()
    var sections: [SectionWords] = []
}

struct InspectorDocumentTab: View {
    let project: Project
    @State private var facts = DocumentFacts()

    var body: some View {
        InspectorDocumentBody(
            model: InspectorDocumentFacts(pages: project.preview.pages.count, words: project.wordCount, facts: facts, sections: project.sectionWords),
            reveal: reveal)
            .task(id: [project.fileRevision, project.wordCount, project.preview.pages.count]) { facts = await project.documentFacts() }
    }

    // The counts come from the compiled document, so a heading is found in the outline by title, level and page.
    private func reveal(_ s: SectionWords) {
        if let h = project.outline.first(where: { $0.level == s.level && $0.title == s.title && $0.page == s.page }) { project.reveal(h) }
    }
}

struct InspectorDocumentBody: View {
    let model: InspectorDocumentFacts
    var reveal: (SectionWords) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
    }

    @ViewBuilder private var content: some View {
        let f = model.facts
        InspectorSection("Statistics") {
            InspectorRow("Pages", model.pages.formatted())
            InspectorRow("Words", model.words.formatted())
            InspectorRow("Characters", String(localized: "\(f.characters.formatted()) in source"))
            InspectorRow("Reading time", InspectorScan.readingMinutes(words: model.words) == 0 ? String(localized: "None") : String(localized: "About \(InspectorScan.readingMinutes(words: model.words)) min at \(InspectorScan.wordsPerMinute) wpm"))
            InspectorRow("Language", f.language?.identifier ?? String(localized: "Not set"))
        }
        InspectorSection("Words per Section") {
            let rows = model.sections.filter { $0.level > 0 || $0.words > 0 }
            if rows.isEmpty { Text("No headings yet.").font(.callout).foregroundStyle(.secondary) }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, s in
                Button { reveal(s) } label: {
                    HStack {
                        Text(s.title.isEmpty ? String(localized: "Before the first heading") : s.title).lineLimit(1).padding(.leading, CGFloat(max(0, s.level - 1)) * 10)
                        Spacer(minLength: 4)
                        Text(s.words.formatted()).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).font(.callout)
                .accessibilityLabel("\(s.title), \(s.words) words").accessibilityHint("Jumps to the section")
            }
        }
        InspectorSection("Packages") {
            if f.packages.isEmpty { Text("No packages imported.").font(.callout).foregroundStyle(.secondary) }
            ForEach(f.packages, id: \.self) { p in
                HStack { Text(p.name); Spacer(); Text("\(p.namespace) \(p.version)").foregroundStyle(.secondary) }
                    .font(.callout).accessibilityElement(children: .combine)
            }
        }
        InspectorSection("Fonts") {
            if f.fonts.isEmpty { Text("No fonts set with text(font:).").font(.callout).foregroundStyle(.secondary) }
            ForEach(f.fonts, id: \.self) { Text($0).font(.callout) }
        }
        InspectorSection("Bibliography") {
            if f.bibEntries == 0 {
                Text("No bibliography entries.").font(.callout).foregroundStyle(.secondary)
            } else {
                InspectorRow("Entries", f.bibEntries.formatted())
                InspectorRow("Uncited", f.uncited.count.formatted())
                ForEach(f.uncited.prefix(30), id: \.self) { Text($0).font(.callout.monospaced()).foregroundStyle(.secondary) }
                if f.uncited.count > 30 { Text("and \(f.uncited.count - 30) more").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}

#Preview("Document") {
    ScrollView {
        InspectorDocumentBody(model: InspectorDocumentFacts(
            pages: 12, words: 4075,
            facts: DocumentFacts(characters: 31_200, language: TextLanguage(lang: "de", region: "CH"),
                                 packages: [PackageUse(namespace: "preview", name: "cetz", version: "0.3.1")], fonts: ["Libertinus Serif", "Inter"],
                                 bibEntries: 14, uncited: ["knuth84", "lamport94"]),
            sections: [SectionWords(title: "Introduction", level: 1, words: 800, page: 0), SectionWords(title: "Method", level: 2, words: 1200, page: 3)]))
            .padding(12)
    }
    .frame(width: 280, height: 640)
}
