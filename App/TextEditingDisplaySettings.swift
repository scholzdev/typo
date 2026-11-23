import SwiftUI
import TypoKit

/// Text Editing › Display, grouped like Xcode's. The defaults match `DisplaySettings`.
struct TextEditingDisplaySettings: View {
    @AppStorage(SettingsKey.lineNumbers) private var lineNumbers = true
    @AppStorage(SettingsKey.foldingRibbon) private var foldingRibbon = true
    @AppStorage(SettingsKey.foldDuration) private var foldDuration = FoldPaper.duration
    @AppStorage(SettingsKey.stickyScroll) private var stickyScroll = true
    @AppStorage(SettingsKey.scopeGuides) private var scopeGuides = "none"
    @AppStorage(SettingsKey.formatWidth) private var formatWidth = 80
    @AppStorage(SettingsKey.formatGuide) private var formatGuide = false
    @AppStorage(SettingsKey.formatOnComplete) private var formatOnComplete = false
    @AppStorage(SettingsKey.highlightOccurrences) private var highlightOccurrences = true
    @AppStorage(SettingsKey.occurrenceDelay) private var occurrenceDelay = 0.25
    @AppStorage(SettingsKey.overscroll) private var overscroll = "none"
    @AppStorage(SettingsKey.wrapLines) private var wrapLines = true
    @AppStorage(SettingsKey.wrapIndent) private var wrapIndent = 0
    @AppStorage(SettingsKey.animatedCaret) private var animatedCaret = true
    @AppStorage(SettingsKey.bracketMatch) private var bracketMatch = true
    @AppStorage(SettingsKey.rainbowBrackets) private var rainbowBrackets = true
    @AppStorage(SettingsKey.colorSwatches) private var colorSwatches = true
    @AppStorage(SettingsKey.colorPickerStyle) private var colorPickerStyle = ColorPickerStyle.wheel
    @AppStorage(SettingsKey.inlayHints) private var inlayHints = false
    @AppStorage(SettingsKey.typewriter) private var typewriter = false

    var body: some View {
        Form {
            Section {
                Toggle("Line numbers", isOn: $lineNumbers)
                Toggle("Code folding ribbon", isOn: $foldingRibbon)
                LabeledContent("Folding animation") {
                    Stepper(foldDuration.formatted(.number.precision(.fractionLength(2))) + " seconds",
                            value: $foldDuration, in: 0.05...2, step: 0.05).monospacedDigit()
                        .accessibilityLabel("Folding animation").accessibilityValue("\(foldDuration) seconds")
                }
                .disabled(!foldingRibbon)
                Toggle("Code structure headers", isOn: $stickyScroll)
                Picker("Scope guides", selection: $scopeGuides) {
                    Text("None").tag("none")
                    Text("Indentation").tag("indentation")
                }
            }
            Section {
                LabeledContent("Reformat code at column") {
                    Stepper("\(formatWidth)", value: $formatWidth, in: 40...200, step: 10).monospacedDigit()
                        .accessibilityLabel("Reformat code at column").accessibilityValue("\(formatWidth)")
                }
                Toggle("Show reformatting guide", isOn: $formatGuide)
                Toggle("Automatically reformat when completing", isOn: $formatOnComplete)
            }
            Section {
                Toggle("Highlight instances of selected symbol", isOn: $highlightOccurrences)
                LabeledContent("Highlighting delay") {
                    Stepper(occurrenceDelay.formatted(.number.precision(.fractionLength(2))) + " seconds",
                            value: $occurrenceDelay, in: 0...2, step: 0.05).monospacedDigit()
                        .accessibilityLabel("Highlighting delay").accessibilityValue("\(occurrenceDelay) seconds")
                }
                .disabled(!highlightOccurrences)
            }
            Section {
                Picker("Editor overscroll", selection: $overscroll) {
                    Text("None").tag("none")
                    Text("Small").tag("small")
                    Text("Medium").tag("medium")
                    Text("Large").tag("large")
                }
            }
            Section("Line Wrapping") {
                Toggle("Wrap lines to editor width", isOn: $wrapLines)
                LabeledContent("Indent wrapped lines") {
                    Stepper("\(wrapIndent) \(wrapIndent == 1 ? "space" : "spaces")", value: $wrapIndent, in: 0...16).monospacedDigit()
                        .accessibilityLabel("Indent wrapped lines").accessibilityValue("\(wrapIndent) spaces")
                }
                .disabled(!wrapLines)
            }
            Section("Decorations") {
                Toggle("Highlight matching brackets", isOn: $bracketMatch)
                Toggle("Rainbow brackets", isOn: $rainbowBrackets)
                Toggle("Color swatches", isOn: $colorSwatches)
                Picker("Color picker", selection: $colorPickerStyle) {
                    ForEach(ColorPickerStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .disabled(!colorSwatches)
                Toggle("Inlay hints", isOn: $inlayHints)
                Toggle("Animated caret", isOn: $animatedCaret)
                Toggle("Typewriter scrolling in Focus Mode", isOn: $typewriter)
            }
        }
        .pane()
    }
}
