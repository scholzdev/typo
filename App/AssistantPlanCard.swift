import SwiftUI
import TypoAssistant

/// The agent's plan in its answer, like a tool row: "Plan" with how much is done, then a checklist that updates in place.
struct AssistantPlanCard: View {
    let plan: AssistantPlan
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checklist").frame(width: 16)
                    Text("Plan")
                    Spacer(minLength: 8)
                    Text("\(plan.completed) of \(plan.entries.count) done").foregroundStyle(.secondary).monospacedDigit()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Plan, \(plan.completed) of \(plan.entries.count) done")
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    // By position: an update keeps the entries in place and changes their status.
                    ForEach(Array(plan.entries.enumerated()), id: \.offset) { _, e in row(e) }
                }
                .transition(.opacity)
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(.easeOut(duration: 0.25), value: plan)
        .animation(.easeOut(duration: 0.2), value: expanded)
    }

    private func row(_ e: AssistantPlan.Entry) -> some View {
        let done = e.status == .completed
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            glyph(e.status)
                .frame(width: 16, height: 16)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            Text(e.content)
                .font(.system(size: 13))
                .strikethrough(done, color: .secondary)
                .foregroundStyle(done ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func glyph(_ s: AssistantPlan.Status) -> some View {
        switch s {
        case .pending: Image(systemName: "circle").foregroundStyle(.secondary).accessibilityLabel("Pending")
        case .inProgress: AssistantSpinner()
        case .completed: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Completed").transition(.scale.combined(with: .opacity))
        }
    }
}
