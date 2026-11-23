import AppKit
import SwiftUI
import TypoKit
import TypstEngine

/// App menu: About with the engine versions, and the acknowledgements window.
struct AboutCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Typo") {
                let credits = "Typst \(EngineVersions.typst) · typstyle \(EngineVersions.typstyle)"
                NSApp.orderFrontStandardAboutPanel(options: [.credits: NSAttributedString(string: credits, attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.secondaryLabelColor])])
            }
            Button("Acknowledgements") { openWindow(id: "acknowledgements") }
        }
    }
}

struct AcknowledgementsView: View {
    private let text = Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "Acknowledgements.txt is missing from the app bundle."

    var body: some View {
        ScrollView { Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding().frame(maxWidth: .infinity, alignment: .leading) }
            .frame(width: 640, height: 520)
    }
}
