import SwiftUI
import TypoKit

/// The table editor's "Live Typeset" pane: the whole table as the document renders it on a page card, or the markup the
/// editor will write.
struct TableTypesetPane: View {
    let model: TableModel
    /// The rendered table (and caption), at `pixelsPerPoint`; nil before the first render or when nothing shows.
    let image: CGImage?
    let pixelsPerPoint: CGFloat
    let rendering: Bool
    @AppStorage("TableEditorTypesetShowsSource") private var showsSource = false
    /// Nil fits the table to the card, the card to the pane.
    @State private var zoom: CGFloat?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(.green).frame(width: 7, height: 7)
                Text("Live Typeset").font(.callout.weight(.semibold))
                if rendering { ProgressView().controlSize(.mini) }
                Spacer()
                Picker("Show", selection: $showsSource) {
                    Text("Document").tag(false)
                    Text("Typst").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            Divider()
            if showsSource { source } else { document }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Live typeset")
    }

    // MARK: Typst

    private var source: some View {
        ScrollView([.vertical, .horizontal]) {
            Text(Self.highlighted("#" + TableCode.render(model)))
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    /// Coloured like the editor; the font is left to the view.
    private static func highlighted(_ text: String) -> AttributedString {
        let s = NSMutableAttributedString(attributedString: Highlighter.attributed(text, path: "table.typ"))
        s.removeAttribute(.font, range: NSRange(location: 0, length: s.length))
        return (try? AttributedString(s, including: \.appKit)) ?? AttributedString(text)
    }

    // MARK: document

    private static let margin: CGFloat = 24, inset: CGFloat = 28

    private var document: some View {
        GeometryReader { geo in
            let fit = max(160, geo.size.width - 2 * Self.margin)
            let scale = image.map { zoom ?? min(1.6, (fit - 2 * Self.inset) / (CGFloat($0.width) / pixelsPerPoint)) } ?? 1
            ZStack(alignment: .bottomTrailing) {
                DotGrid()
                ScrollView([.vertical, .horizontal]) {
                    page(fit: fit, scale: scale)
                        .padding(Self.margin)
                        .frame(minWidth: geo.size.width, minHeight: geo.size.height)
                }
                if image != nil { zoomPill(scale) }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder private func page(fit: CGFloat, scale: CGFloat) -> some View {
        if let image {
            let size = CGSize(width: CGFloat(image.width) / pixelsPerPoint * scale, height: CGFloat(image.height) / pixelsPerPoint * scale)
            let width = zoom == nil ? fit : size.width + 2 * Self.inset
            VStack(alignment: .leading, spacing: 9) {
                skeleton([1, 0.94, 0.58], width: width - 2 * Self.inset)
                Image(decorative: image, scale: pixelsPerPoint)
                    .resizable()
                    .frame(width: size.width, height: size.height)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .accessibilityLabel("The table as typeset")
                skeleton([0.97, 0.72], width: width - 2 * Self.inset)
            }
            .padding(Self.inset)
            .frame(width: width)
            .background(.white, in: RoundedRectangle(cornerRadius: 3))
            .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
        } else {
            ContentUnavailableView(rendering ? "Typesetting…" : "No Preview", systemImage: "tablecells",
                                   description: Text(rendering ? "" : "Nothing of the table shows on a page yet."))
        }
    }

    /// Grey bars standing for the text around the table on the page.
    private func skeleton(_ fractions: [CGFloat], width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(fractions.indices, id: \.self) { i in
                Capsule().fill(.black.opacity(0.07)).frame(width: max(0, width * fractions[i]), height: 6)
            }
        }
        .accessibilityHidden(true)
    }

    private func zoomPill(_ scale: CGFloat) -> some View {
        HStack(spacing: 2) {
            Button("Zoom Out", systemImage: "minus") { zoom = max(0.25, scale / 1.25) }
            Button("Fit") { zoom = nil }
                .labelStyle(.titleOnly)
                .fontWeight(zoom == nil ? .semibold : .regular)
            Button("Zoom In", systemImage: "plus") { zoom = min(4, scale * 1.25) }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
        .padding(12)
    }
}

/// The pane's faint dotted background.
private struct DotGrid: View {
    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 14
            var path = Path()
            for x in stride(from: step / 2, to: size.width, by: step) {
                for y in stride(from: step / 2, to: size.height, by: step) { path.addEllipse(in: CGRect(x: x, y: y, width: 1.6, height: 1.6)) }
            }
            ctx.fill(path, with: .color(.secondary.opacity(0.35)))
        }
        .accessibilityHidden(true)
    }
}
