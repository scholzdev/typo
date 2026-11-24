import AppKit
import SwiftUI
import TypoKit

extension SettingsKey {
    static let presenterCurrent = "presenterShowsCurrent"
    static let presenterNext = "presenterShowsNext"
    static let presenterNotes = "presenterShowsNotes"
    static let presenterReady = "presenterShowsReady"
    static let presenterClock = "presenterShowsClock"
    static let presenterTimer = "presenterShowsTimer"
    static let presenterTimerRemaining = "presenterTimerRemaining"
    static let presenterTimerDuration = "presenterTimerDuration"
    static let presenterNotesSize = "presenterNotesSize"
    static let presenterNotesInverted = "presenterNotesInverted"
}

/// The speaker's window, laid out like Keynote's presenter display.
/// It shares page and keys with the presentation; closing it ends the presentation, as the slides take no keys.
struct PresenterWindow: View {
    let id: PresenterID
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var session: PresentationSession?

    var body: some View {
        Group {
            if let session { PresenterContent(session: session) } else { Color.clear }
        }
        .frame(minWidth: 720, minHeight: 460)
        .background(Color(white: 0.067))
        .environment(\.colorScheme, .dark)
        .navigationTitle(session.map { String(localized: "Presenter View – \($0.project.main.raw)") } ?? String(localized: "Presenter View"))
        .task {
            session = await PresentationSession.attach(id.project)
            if session == nil { dismissWindow(value: id) }
        }
        .onDisappear { session?.detach(); session?.end() }
        .background { OnScreen(screen: session?.home) { session?.presenterWindow = $0 } }
        .onChange(of: session?.ended == true) { _, ended in if ended { dismissWindow(value: id) } }
        .task(id: session.map { $0.project.preview.pages.map(\.hash) }) {
            guard let session else { return }
            let notes = await session.project.presenterNotes()
            if !Task.isCancelled { session.notes = notes }
        }
    }
}

/// Moves the hosting window onto `screen` once, so the presenter view never opens under the slides on the other display.
private struct OnScreen: NSViewRepresentable {
    let screen: NSScreen?
    let found: (Int) -> Void
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ probe: Probe, context: Context) { probe.screen = screen; probe.found = found; probe.place() }

    final class Probe: NSView {
        var screen: NSScreen?
        var found: ((Int) -> Void)?
        private var placed = false
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); place() }
        func place() {
            if let window { found?(window.windowNumber) }
            guard !placed, let screen, let window else { return }
            placed = true
            guard window.screen != screen else { return }
            let size = window.frame.size, area = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2))
        }
    }
}

private struct PresenterContent: View {
    let session: PresentationSession
    @AppStorage(SettingsKey.presenterCurrent) private var showsCurrent = true
    @AppStorage(SettingsKey.presenterNext) private var showsNext = true
    @AppStorage(SettingsKey.presenterNotes) private var showsNotes = true
    @AppStorage(SettingsKey.presenterReady) private var showsReady = true
    @AppStorage(SettingsKey.presenterClock) private var showsClock = true
    @AppStorage(SettingsKey.presenterTimer) private var showsTimer = true
    @AppStorage(SettingsKey.presenterTimerRemaining) private var timerRemaining = false
    @AppStorage(SettingsKey.presenterTimerDuration) private var timerDuration = 0
    @AppStorage(SettingsKey.presenterNotesSize) private var notesSize = 28.0
    @AppStorage(SettingsKey.presenterNotesInverted) private var notesInverted = false
    @State private var controls = false
    @State private var moves = 0
    @State private var layoutShown = false
    @State private var shortcutsShown = false
    @State private var navigatorShown = false
    @State private var refocus = 0
    @State private var notesScroll = ScrollPosition()
    @State private var notesOffset: CGFloat = 0

    private static let clockColor = Color(red: 0.62, green: 0.80, blue: 0.95)
    private static let timerColor = Color(red: 0.95, green: 0.94, blue: 0.85)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            VStack(spacing: 0) {
                if showsReady { readyBar.frame(height: max(6, h * 0.012)) }
                header(h).padding(.horizontal, w * 0.028).frame(height: h * 0.14)
                slides(w, h)
                if showsNotes { notesPanel.frame(height: h / 3).padding(.horizontal, w * 0.028) }
                if navigatorShown { navigator }
            }
        }
        .overlay { if shortcutsShown { ShortcutsOverlay { shortcutsShown = false } } }
        .modifier(SlideKeys(session: session, refocus: refocus))
        .onKeyPress(characters: CharacterSet(charactersIn: "+=")) { _ in notesSize = min(notesSize + 4, 96); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "-_")) { _ in notesSize = max(notesSize - 4, 12); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "uU")) { _ in scrollNotes(-1) }
        .onKeyPress(characters: CharacterSet(charactersIn: "dD")) { _ in scrollNotes(1) }
        .onKeyPress(characters: CharacterSet(charactersIn: "?/")) { _ in shortcutsShown.toggle(); return .handled }
        .onKeyPress(.escape) {   // Escape closes the shortcuts first; only then it ends the presentation
            guard shortcutsShown else { return .ignored }
            shortcutsShown = false
            return .handled
        }
        .onContinuousHover { if case .active = $0 { controls = true; moves += 1 } }
        .task(id: moves) {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled, !layoutShown { controls = false }
        }
        .onChange(of: layoutShown) { _, shown in if !shown { refocus += 1; moves += 1 } }
        .onChange(of: shortcutsShown) { refocus += 1 }
    }

    /// Keynote's ready-to-advance bar: red while the slides display is still rendering the next slide.
    private var readyBar: some View {
        let page = session.page
        let ready = !session.showsSlides || page + 1 >= session.count || session.readyPage == page + 1
        return (ready ? Color(red: 0.2, green: 0.85, blue: 0.3) : Color(red: 0.9, green: 0.15, blue: 0.15))
            .accessibilityElement()
            .accessibilityLabel(ready ? "Ready to advance" : "Not ready to advance")
    }

    private func header(_ h: CGFloat) -> some View {
        ZStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: h * 0.2) {
                    if showsClock {
                        Text(context.date, format: .dateTime.hour().minute().second())
                            .foregroundStyle(Self.clockColor)
                            .accessibilityLabel("Clock")
                    }
                    if showsTimer {
                        let clock = session.show.clock
                        Button { session.show.clock.toggle(at: .now) } label: {
                            Text(clock.readout(at: context.date, remainingOf: timerRemaining ? timerDuration : nil))
                                .foregroundStyle(Self.timerColor)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .help("Click to pause or resume the timer; R resets it")
                        .accessibilityLabel(timerRemaining ? "Time Remaining" : "Time Elapsed")
                    }
                }
                .font(.system(size: h * 0.085, weight: .light).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            }
            HStack {
                Button(navigatorShown ? "Hide Navigator" : "Show Navigator") { navigatorShown.toggle() }
                    .buttonStyle(.bordered)
                Spacer()
                HStack(spacing: h * 0.03) {
                    glyph("Keyboard Shortcuts", "questionmark.circle.fill") { shortcutsShown.toggle() }
                    glyph("Layout", "rectangle.split.2x1") { layoutShown = true }
                        .popover(isPresented: $layoutShown, arrowEdge: .bottom) { layoutOptions }
                    glyph("Swap Displays", "rectangle.2.swap") { session.swapDisplays() }
                    glyph("End Presentation", "xmark") { session.end() }
                }
                .font(.system(size: max(16, h * 0.024), weight: .semibold))
            }
            .focusable(false)
            .opacity(controls ? 1 : 0)
            .allowsHitTesting(controls)
            .animation(.easeInOut(duration: 0.3), value: controls)
        }
    }

    private func glyph(_ title: LocalizedStringKey, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(title, systemImage: symbol, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(Color(white: 0.55))
            .help(title)
            .focusable(false)
    }

    private func slides(_ w: CGFloat, _ h: CGFloat) -> some View {
        let preview = session.project.preview, pages = preview.pages, page = session.page
        let label = Font.system(size: max(13, h / 35))
        return HStack(alignment: .center, spacing: w * 0.02) {
            if pages.indices.contains(page) {
                if showsCurrent {
                    VStack(spacing: h * 0.012) {
                        Text("Current: Slide \(page + 1) of \(pages.count)").font(label).lineLimit(1)
                        Slide(preview: preview, page: pages[page])
                            .aspectRatio(pages[page].size, contentMode: .fit)
                            .border(Color(white: 0.2))
                            .overlay(alignment: .top) { blankBadge }
                            .onTapGesture { session.move(1) }
                    }
                    .frame(width: w * 0.55)
                }
                if showsNext {
                    VStack(spacing: h * 0.012) {
                        let next = pages.indices.contains(page + 1) ? pages[page + 1] : nil
                        Text(next == nil ? "End of Show" : "Next").font(label).lineLimit(1)
                        Group {
                            if let next { Slide(preview: preview, page: next).onTapGesture { session.move(1) } } else { Color.black }
                        }
                        .aspectRatio((next ?? pages[page]).size, contentMode: .fit)
                        .border(Color(white: 0.2))
                    }
                    .frame(width: w * 0.39)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.vertical, h * 0.02)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var blankBadge: some View {
        if let blank = session.blank {
            Text(blank == .white ? "Slides are white – press W" : "Slides are black – press B")
                .font(.title3).padding(8).background(.black.opacity(0.7), in: .capsule).padding(8)
        }
    }

    private var notesPanel: some View {
        let page = session.page
        let text = PresenterNotes.texts(session.notes)[page]
        let note = session.notes.first { $0.pages.contains(page) }
        return VStack(spacing: 0) {
            ZStack {
                Text("Presenter Notes").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Button { notesSize = max(notesSize - 4, 12) } label: { Text(verbatim: "A").font(.system(size: 9)) }
                        .accessibilityLabel("Smaller Notes Font")
                    Button { notesSize = min(notesSize + 4, 96) } label: { Text(verbatim: "A").font(.system(size: 13, weight: .semibold)) }
                        .accessibilityLabel("Larger Notes Font")
                    Button("Invert Colors") { notesInverted.toggle() }
                    Spacer()
                    Button("Edit") { if let note { session.project.reveal(note) } }
                        .disabled(note == nil)
                        .help("Show the note in the editor")
                }
                .controlSize(.small)
                .focusable(false)
            }
            .padding(4)
            Divider()
            ScrollView {
                Text(text ?? String(localized: "No notes for this slide."))
                    .font(.system(size: notesSize))
                    .foregroundStyle(text == nil ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(12)
            }
            .scrollPosition($notesScroll)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in notesOffset = y }
            .onChange(of: page) { notesScroll.scrollTo(edge: .top) }
            .accessibilityLabel("Presenter Notes")
        }
        .background(notesInverted ? Color.black : Color.white)
        .environment(\.colorScheme, notesInverted ? .dark : .light)
    }

    private func scrollNotes(_ direction: CGFloat) -> KeyPress.Result {
        withAnimation { notesScroll.scrollTo(y: max(0, notesOffset + direction * notesSize * 3)) }
        return .handled
    }

    private var navigator: some View {
        let preview = session.project.preview, page = session.page
        return ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(preview.pages) { p in
                        Button { session.go(to: p.id) } label: {
                            Thumbnail(page: p, preview: preview, selected: p.id == page, width: 120)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .id(p.id)
                    }
                }
                .padding(12)
            }
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: page, initial: true) { _, p in withAnimation { proxy.scrollTo(p, anchor: .center) } }
        }
        .background(.black.opacity(0.4))
    }

    private var layoutOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Current Slide", isOn: $showsCurrent)
            Toggle("Next Slide", isOn: $showsNext)
            Toggle("Presenter Notes", isOn: $showsNotes)
            Toggle("Ready to Advance Indicator", isOn: $showsReady)
            Toggle("Clock", isOn: $showsClock)
            HStack(alignment: .top, spacing: 12) {
                Toggle("Timer", isOn: $showsTimer)
                Picker("Timer", selection: $timerRemaining) {
                    Text("Elapsed").tag(false)
                    Text("Remaining").tag(true)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .disabled(!showsTimer)
                DurationField(seconds: $timerDuration)
                    .disabled(!showsTimer || !timerRemaining)
            }
        }
        .toggleStyle(.checkbox)
        .padding(14)
    }
}

/// The talk's length for a remaining-time timer, typed as `mm:ss`.
private struct DurationField: View {
    @Binding var seconds: Int
    @State private var text = ""

    var body: some View {
        TextField("Duration", text: $text, prompt: Text(verbatim: "mm:ss"))
            .labelsHidden()
            .monospacedDigit()
            .multilineTextAlignment(.center)
            .frame(width: 64)
            .onAppear { text = PresentationClock.minutesSeconds(seconds) }
            .onSubmit(commit)
            .onDisappear(perform: commit)
    }

    private func commit() {
        if let s = PresentationClock.seconds(from: text) { seconds = s }
        text = PresentationClock.minutesSeconds(seconds)
    }
}

/// Keynote's `?` panel: the playback keys.
private struct ShortcutsOverlay: View {
    let close: () -> Void

    private var rows: [(LocalizedStringKey, LocalizedStringKey)] {
        [("→  ↓  Space  Page Down", "Go to next slide"),
         ("←  ↑  Page Up", "Go to previous slide"),
         ("Home  /  End", "Go to first or last slide"),
         ("Slide number, then Return", "Go to that slide"),
         ("B", "Show or hide a black screen"),
         ("W", "Show or hide a white screen"),
         ("X", "Swap displays"),
         ("+  /  −", "Larger or smaller notes font"),
         ("U  /  D", "Scroll notes up or down"),
         ("R", "Reset timer"),
         ("?", "Show or hide keyboard shortcuts"),
         ("Esc", "End presentation")]
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).onTapGesture(perform: close)
            VStack(alignment: .leading, spacing: 14) {
                Text("Keyboard Shortcuts").font(.title2.bold())
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    ForEach(rows.indices, id: \.self) { i in
                        GridRow {
                            Text(rows[i].0).fontWeight(.semibold).gridColumnAlignment(.trailing)
                            Text(rows[i].1).foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.title3)
            }
            .padding(28)
            .background(Color(white: 0.15), in: .rect(cornerRadius: 14))
            .onTapGesture(perform: close)
        }
    }
}
