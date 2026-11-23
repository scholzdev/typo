import AppKit
import SwiftUI
import TypoKit

enum InspectorTab: String, CaseIterable, Identifiable {
    case file, document, selection
    var id: Self { self }
    var symbol: String {
        switch self {
        case .file: "doc"
        case .document: "doc.text.magnifyingglass"
        case .selection: "slider.horizontal.3"
        }
    }
    var title: String {
        switch self {
        case .file: "File"
        case .document: "Document"
        case .selection: "Selection"
        }
    }
}

/// Xcode's inspector column: an icon tab bar over File, Document and Selection.
struct InspectorView: View {
    let project: Project
    let sidebar: SidebarModel
    let actions: EditorActions
    let tables: TableEditing
    var browseFonts: () -> Void = {}
    @AppStorage("inspector.tab") private var tab = InspectorTab.file

    var body: some View {
        VStack(spacing: 0) {
            Picker("Inspector", selection: $tab) {
                ForEach(InspectorTab.allCases) { t in
                    Image(systemName: t.symbol).accessibilityLabel(t.title).help(t.title).tag(t)
                }
            }
            .pickerStyle(.segmented).labelsHidden().padding(8)
            Divider()
            ScrollView {
                Group {
                    switch tab {
                    case .file: InspectorFileTab(project: project, file: sidebar.quickLook ?? project.selectedFile)
                    case .document: InspectorDocumentTab(project: project)
                    case .selection: InspectorSelectionTab(project: project, actions: actions, tables: tables, browseFonts: browseFonts)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
        }
        .inspectorColumnWidth(min: 240, ideal: 280, max: 420)
        .accessibilityElement(children: .contain).accessibilityLabel("Inspector")
    }
}

/// A titled group of rows, Xcode style.
struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content
        }
        .padding(.bottom, 14).frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain).accessibilityLabel(title)
    }
}

/// "Label: value" with the value selectable.
struct InspectorRow: View {
    let label: String
    let value: String
    init(_ label: String, _ value: String) { self.label = label; self.value = value }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary).frame(width: 84, alignment: .trailing)
            Text(value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }
}

/// A text box that writes on Return or when it loses focus, and only when the text changed.
struct InspectorField: View {
    let title: String
    let value: String
    let commit: (String) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary).frame(width: 84, alignment: .trailing)
            TextField(title, text: $draft).textFieldStyle(.roundedBorder).focused($focused)
                .onSubmit { send() }
                .accessibilityLabel(title)
        }
        .font(.callout)
        .onAppear { draft = value }
        .onChange(of: value) { if !focused { draft = value } }
        .onChange(of: focused) { if !focused { send() } }
    }

    private func send() { if draft != value { commit(draft) } }
}
