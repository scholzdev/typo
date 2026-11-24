import SwiftUI

/// Cancel + default action at the trailing edge of a sheet footer; the caller supplies the HStack and Spacer.
struct SheetButtons: View {
    let ok: LocalizedStringKey
    var disabled = false
    var shortcut: KeyboardShortcut = .defaultAction
    let cancel: () -> Void
    let action: () -> Void

    var body: some View {
        Button("Cancel", role: .cancel, action: cancel).keyboardShortcut(.cancelAction).buttonStyle(.glass)
        Button(ok, action: action).keyboardShortcut(shortcut).buttonStyle(.glassProminent).disabled(disabled)
    }
}

/// A plain full-width list row that is clickable across its whole area.
struct RowButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button(action: action) {
            label.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension View {
    /// A rounded Liquid Glass search field with a leading magnifying glass, as in the bibliography header.
    func glassSearchField() -> some View {
        textFieldStyle(.plain)
            .padding(.leading, 20)
            .overlay(alignment: .leading) { Image(systemName: "magnifyingglass").foregroundStyle(.secondary) }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
    }

    /// Accent-tinted interactive glass capsule when selected (EditorTabs.swift 56-58 repeats this; adopt when it is free).
    func selectableGlassCapsule(_ on: Bool) -> some View {
        glassEffect(on ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: .capsule)
    }
}
