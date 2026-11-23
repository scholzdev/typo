import SwiftUI
import TypoKit

/// The bottom bar's word count as a button: opens the goal, today's words and the per-chapter counts.
struct WordCountButton: View {
    let project: Project
    let actions: EditorActions
    @State private var progress = WritingProgress()
    @State private var shown = false

    private var store: ProgressStore { ProgressStore(project.id) }

    var body: some View {
        Button { shown.toggle() } label: {
            HStack(spacing: 5) {
                Text(WordCount.label(total: project.wordCount, selected: actions.selectedWords, goal: progress.goal))
                    .monospacedDigit()
                if let f = progress.fraction(total: project.wordCount) {
                    ZStack {
                        Circle().stroke(.quaternary, lineWidth: 2)
                        Circle().trim(from: 0, to: f).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round)).rotationEffect(.degrees(-90))
                    }
                    .frame(width: 10, height: 10)
                }
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help("Counts the words you wrote in the document and its included files; numbering, captions\u{2019} labels, references, page numbers and code do not count. With a selection: the words of the selected text. Click for your goal and the words per chapter.")
        .popover(isPresented: $shown, arrowEdge: .top) { ProgressPopover(project: project, progress: $progress, save: { store.save(progress) }) }
        .onAppear { progress = store.load(); record() }
        .onChange(of: project.sectionWords) { record() }
    }

    /// Only once a count exists, so a launch before the first compile does not make the whole text "today's".
    private func record() {
        guard !project.sectionWords.isEmpty else { return }
        progress.record(total: project.wordCount, on: .now)
        store.save(progress)
    }
}

struct ProgressPopover: View {
    let project: Project
    @Binding var progress: WritingProgress
    let save: () -> Void
    @State private var goalText = ""

    private struct Chapter: Identifiable { let id: Int; var title: String; var level: Int; var page: Int; var words: Int }

    /// Level-1 sections with their deeper sections summed in; the text before the first heading only when there is some.
    private var chapters: [Chapter] {
        var rows: [Chapter] = []
        for (i, s) in project.sectionWords.enumerated() {
            if s.level <= 1 || (rows.last?.level ?? 0) == 0 {
                rows.append(Chapter(id: i, title: s.title, level: s.level, page: s.page, words: s.words))
            } else {
                rows[rows.count - 1].words += s.words
            }
        }
        return rows.filter { $0.level > 0 || $0.words > 0 }
    }

    var body: some View {
        let total = project.wordCount
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Goal")
                TextField("No goal", text: $goalText)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                    .onChange(of: goalText) {
                        let n = Int(goalText.filter(\.isNumber))
                        progress.goal = n.flatMap { $0 > 0 ? $0 : nil }
                        save()
                    }
                Text("words").foregroundStyle(.secondary)
            }
            if let f = progress.fraction(total: total) {
                ProgressView(value: f)
                Text("\(total.formatted()) of \(progress.goal!.formatted()) words (\(Int(f * 100)) %)").font(.caption).foregroundStyle(.secondary)
            }
            let today = progress.today(total: total)
            Text("Today: \(today >= 0 ? "+" : "\u{2212}")\(abs(today).formatted()) words").monospacedDigit()
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(chapters) { c in
                        RowButton { reveal(c) } label: {
                            HStack {
                                Text(c.title.isEmpty ? (c.level == 0 ? "Front matter" : "Untitled") : c.title).lineLimit(1)
                                Spacer(minLength: 12)
                                Text(c.words.formatted()).monospacedDigit().foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
            .frame(maxHeight: 260)
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { goalText = progress.goal.map(String.init) ?? "" }
    }

    // The counts come from the compiled document, so a heading is found in the outline by title, level and page.
    private func reveal(_ c: Chapter) {
        if let h = project.outline.first(where: { $0.level == c.level && $0.title == c.title && $0.page == c.page }) { project.reveal(h) }
    }
}
