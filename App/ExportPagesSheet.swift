import AppKit
import SwiftUI
import TypoKit
import TypstEngine

/// Asks which pages File › Export › PDF writes, laid out like the print dialog: the pages on the left with a tick
/// each, and All / Range / Selection on the right. Nil when the user cancels.
@MainActor func choosePDFPages(_ project: Project, pageCount: Int) async -> PageSelection? {
    guard let window = NSApp.keyWindow else { return .all }
    return await withCheckedContinuation { done in
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        sheet.contentViewController = NSHostingController(rootView: ExportPagesView(preview: project.preview, pageCount: pageCount) { choice in
            window.endSheet(sheet)
            done.resume(returning: choice)
        })
        window.beginSheet(sheet)
    }
}

private struct ExportPagesView: View {
    let preview: PreviewModel
    let pageCount: Int
    let finish: (PageSelection?) -> Void

    private enum Kind { case all, range, selection }
    @State private var kind = Kind.all
    @State private var from = 1
    @State private var to: Int
    @State private var ticked: Set<Int>

    init(preview: PreviewModel, pageCount: Int, finish: @escaping (PageSelection?) -> Void) {
        self.preview = preview
        self.pageCount = pageCount
        self.finish = finish
        _to = State(initialValue: pageCount)
        _ticked = State(initialValue: Set(1...pageCount))
    }

    private var selection: PageSelection {
        switch kind {
        case .all: .all
        case .range: .range(from: from, to: to)
        case .selection: .pages(ticked)
        }
    }

    private func included(_ page: Int) -> Bool {
        switch kind {
        case .all: true
        case .range: (min(from, to)...max(from, to)).contains(page)
        case .selection: ticked.contains(page)
        }
    }

    /// Ticking a page switches to Selection, starting from the pages the current choice covers.
    private func toggle(_ page: Int) {
        if kind != .selection { ticked = Set((1...pageCount).filter(included)) }
        kind = .selection
        if ticked.contains(page) { ticked.remove(page) } else { ticked.insert(page) }
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(preview.pages.prefix(pageCount)) { page in
                        ExportThumbnail(page: page, preview: preview, pageCount: pageCount, on: included(page.id + 1)) { toggle(page.id + 1) }
                    }
                }
                .padding(16)
            }
            .frame(width: 220)
            .background(.quaternary.opacity(0.5))
            VStack(spacing: 0) {
                Form {
                    Section("Pages") {
                        radio(.all) { Text("All \(pageCount) Pages") }
                        radio(.range) {
                            HStack {
                                Text("Range from")
                                pageField($from)
                                Text("to")
                                pageField($to)
                            }
                        }
                        radio(.selection) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Selection")
                                Text("Select pages in the sidebar").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .formStyle(.grouped)
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { finish(nil) }.keyboardShortcut(.cancelAction)
                    Button("Export…") { finish(selection) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(selection.spans(pageCount: pageCount)?.isEmpty == true)
                }
                .padding(16)
            }
        }
        .frame(width: 680, height: 500)
    }

    private func radio(_ k: Kind, @ViewBuilder label: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // As in the print dialog: a filled grey dot when off, the accent colour with a white centre when on.
            ZStack {
                Circle().fill(kind == k ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                if kind == k { Circle().fill(.white).frame(width: 6, height: 6) }
            }
            .frame(width: 16, height: 16)
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            .accessibilityHidden(true)
            label()
        }
        .contentShape(.rect)
        .onTapGesture { kind = k }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(kind == k ? [.isButton, .isSelected] : .isButton)
    }

    private func pageField(_ value: Binding<Int>) -> some View {
        TextField("", value: value, format: .number)
            .labelsHidden().textFieldStyle(.plain).multilineTextAlignment(.trailing)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.separator))
            .frame(width: 64)
            .onChange(of: value.wrappedValue) { _, v in
                let clamped = min(max(v, 1), pageCount)
                if clamped != v { value.wrappedValue = clamped }
                kind = .range
            }
    }
}

private struct ExportThumbnail: View {
    let page: PageInfo
    let preview: PreviewModel
    let pageCount: Int
    let on: Bool
    let toggle: () -> Void
    @Environment(\.displayScale) private var displayScale
    private static let width: CGFloat = 180

    var body: some View {
        let key = ImageKey(page.hash, pixelsPerPoint: displayScale * Self.width / page.size.width)
        PageImage(image: preview.image(for: key), dark: false)
            .aspectRatio(page.size, contentMode: .fit)
            .frame(width: Self.width)
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            .overlay(alignment: .bottom) {
                Button(action: toggle) {
                    Label { Text("Page \(page.id + 1) of \(pageCount)") } icon: {
                        Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    }
                    .font(.callout)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 10)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            .onTapGesture(perform: toggle)
            .task(id: key) { await preview.render(page, key, thumbnail: true) }
    }
}
