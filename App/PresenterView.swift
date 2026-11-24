import AppKit
import SwiftUI
import TypoKit

/// The speaker's window: current and next slide, speaker notes, slide number, time of day and a timer.
/// It shares page and keys with the presentation; closing it leaves the presentation running.
struct PresenterWindow: View {
    let id: PresenterID
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var session: PresentationSession?

    var body: some View {
        Group {
            if let session { PresenterContent(session: session) } else { Color.clear }
        }
        .frame(minWidth: 720, minHeight: 460)
        .background(Color(white: 0.08))
        .environment(\.colorScheme, .dark)
        .modifier(SlideKeys(session: session))
        .navigationTitle(session.map { String(localized: "Presenter View – \($0.project.main.raw)") } ?? String(localized: "Presenter View"))
        .task {
            session = await PresentationSession.attach(id.project)
            if session == nil { dismissWindow(value: id) }
        }
        .onDisappear { session?.detach() }
        .background { OnScreen(screen: session?.home) }
        .onChange(of: session?.ended == true) { _, ended in if ended { dismissWindow(value: id) } }
        .task(id: session.map { $0.project.preview.pages.map(\.hash) }) {
            guard let session else { return }
            let notes = await session.project.speakerNotes()
            if !Task.isCancelled { session.notes = notes }
        }
    }
}

/// Moves the hosting window onto `screen` once, so the presenter view never opens under the slides on the other display.
private struct OnScreen: NSViewRepresentable {
    let screen: NSScreen?
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ probe: Probe, context: Context) { probe.screen = screen; probe.place() }

    final class Probe: NSView {
        var screen: NSScreen?
        private var placed = false
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); place() }
        func place() {
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
    private let big = Font.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit()

    var body: some View {
        let preview = session.project.preview, pages = preview.pages, page = session.page
        VStack(spacing: 20) {
            GeometryReader { geo in
                HStack(alignment: .top, spacing: 24) {
                    if pages.indices.contains(page) {
                        Slide(preview: preview, page: pages[page])
                            .onTapGesture { session.move(1) }
                            .overlay(alignment: .top) {
                                if session.blackout {
                                    Text("Slides are black – press B").font(.title3).padding(8).background(.black.opacity(0.7), in: .capsule)
                                }
                            }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Next").font(.title3).foregroundStyle(.secondary)
                        if pages.indices.contains(page + 1) {
                            Slide(preview: preview, page: pages[page + 1])
                                .aspectRatio(pages[page + 1].size, contentMode: .fit)
                                .onTapGesture { session.move(1) }
                        } else {
                            Text("End of presentation").font(.title2).foregroundStyle(.secondary)
                        }
                        Text("Notes").font(.title3).foregroundStyle(.secondary).padding(.top, 12)
                        ScrollView {
                            Text(session.notes[page] ?? String(localized: "No notes for this slide."))
                                .font(.title2)
                                .foregroundStyle(session.notes[page] == nil ? .secondary : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityLabel("Speaker notes")
                    }
                    .frame(width: geo.size.width * 0.3)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 32) {
                Text("\(page + 1) / \(pages.count)")
                    .font(big)
                    .accessibilityLabel("Slide \(page + 1) of \(pages.count)")
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(alignment: .firstTextBaseline, spacing: 32) {
                        Text(context.date, format: .dateTime.hour().minute())
                            .font(big).foregroundStyle(.secondary)
                            .accessibilityLabel("Time of day")
                            .accessibilityValue(Text(context.date, format: .dateTime.hour().minute()))
                        let elapsed = Duration.seconds(Int(session.show.clock.elapsed(at: context.date))).formatted(.time(pattern: .hourMinuteSecond))
                        Text(elapsed)
                            .font(big)
                            .accessibilityLabel("Elapsed time")
                            .accessibilityValue(elapsed)
                    }
                }
                timerButtons
            }
        }
        .padding(24)
    }

    private var timerButtons: some View {
        let running = session.show.clock.isRunning
        return HStack(spacing: 12) {
            Button(running ? "Pause Timer" : "Start Timer", systemImage: running ? "pause.fill" : "play.fill") {
                session.show.clock.toggle(at: .now)
            }
            Button("Reset Timer", systemImage: "arrow.counterclockwise") { session.show.clock.reset() }
        }
        .labelStyle(.iconOnly)
        .controlSize(.large)
        // Space must move the slides, never press a focused button.
        .focusable(false)
    }
}
