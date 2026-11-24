import SwiftUI
import TypoKit

extension SettingsKey {
    static let bottomAreaShown = "bottomAreaShown"
    static let bottomAreaHeight = "bottomAreaHeight"
}

/// Xcode's debug area: visibility and height (persisted).
@MainActor @Observable final class BottomAreaModel {
    var isShown = UserDefaults.standard.object(forKey: SettingsKey.bottomAreaShown) as? Bool ?? false {
        didSet { UserDefaults.standard.set(isShown, forKey: SettingsKey.bottomAreaShown) }
    }
    var height = UserDefaults.standard.object(forKey: SettingsKey.bottomAreaHeight) as? Double ?? 170
    /// The editor column's height, for the 75 % clamp.
    var available: CGFloat = 0

    var clamped: CGFloat { min(max(height, 120), max(available * 0.75, 120)) }
    func persistHeight() { UserDefaults.standard.set(height, forKey: SettingsKey.bottomAreaHeight) }
}

/// The issues list under the debug bar; the top edge drags to resize.
struct BottomArea: View {
    let project: Project
    let model: BottomAreaModel
    @State private var startHeight: Double?
    @State private var issueFilter = ""

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay { Color.clear.frame(height: 8).contentShape(Rectangle()).pointerStyle(.rowResize).gesture(resize) }
            issues
        }
        .frame(height: model.clamped)
        .background(Color(nsColor: .textBackgroundColor))
        .modifier(FadeIn())
    }

    private var resize: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { v in
                let start = startHeight ?? model.clamped
                startHeight = start
                model.height = start - v.translation.height
            }
            .onEnded { _ in startHeight = nil; model.height = model.clamped; model.persistHeight() }
    }

    private var issues: some View {
        let all = project.diagnostics.filter { issueFilter.isEmpty || $0.message.localizedStandardContains(issueFilter) }
        return VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if all.isEmpty { Text("No Issues").foregroundStyle(.secondary) }
                    ForEach(all) { IssueRow(project: project, diagnostic: $0) }
                }
                .padding(8)
            }
            footer(filter: $issueFilter)
        }
    }

    private func footer(filter: Binding<String>) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease.circle").foregroundStyle(.secondary)
            TextField("Filter", text: filter).textFieldStyle(.plain).accessibilityLabel("Filter")
        }
        .font(.system(size: 11))
        .padding(.horizontal, 8).frame(height: 24)
        .background(.background.secondary)
        .overlay(alignment: .top) { Divider() }
    }
}

/// Fades a pane in as it appears. Only the opacity animates: an animated height change of the bottom inset made
/// the split views re-layout every frame until AppKit gave up ("more Update Constraints in Window passes than views").
struct FadeIn: ViewModifier {
    @State private var shown = false
    func body(content: Content) -> some View {
        content.opacity(shown ? 1 : 0).onAppear { withAnimation(.easeOut(duration: 0.18)) { shown = true } }
    }
}
