import AppKit
import SwiftUI
import TypoKit
import TypstEngine

struct PreviewView: View {
    let project: Project
    private var preview: PreviewModel { project.preview }
    @State private var position = ScrollPosition()
    @State private var visible = CGRect.zero        // visible rect in scroll content coordinates
    /// The page a thumbnail or Go to Page asked for. It stays the current page while it is on screen, so the last
    /// page counts as current even when the scroll view cannot bring it to the top.
    @State private var jumped: Int?

    private static let inset = PreviewMath.pageInset      // LazyVStack padding and page spacing

    var body: some View {
        HStack(spacing: 0) {
            if preview.showsThumbnails && !preview.pages.isEmpty {
                ThumbnailStrip(project: project)
                Divider()
            }
            pages
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .overlay { if preview.pages.isEmpty { ContentUnavailableView("No Preview", systemImage: "doc") } }
        .overlay(alignment: .bottom) { if preview.isStale { StaleBanner() } }
        .animation(.default, value: preview.isStale)
    }

    private var pages: some View {
        GeometryReader { geo in
            // Zoom 1 fits the column; the margin also leaves room for a legacy scroller (always shown with a mouse),
            // which is 16 pt or more: with exactly 16 the page was a point too wide and a horizontal scroller appeared.
            let fit = max(1, geo.size.width - 2 * Self.inset - 20)
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: Self.inset) {
                    ForEach(PreviewMath.rows(count: preview.pages.count, columns: preview.columns), id: \.lowerBound) { row in
                        HStack(alignment: .top, spacing: Self.inset) {
                            ForEach(preview.pages[row]) { PageView(page: $0, project: project, fitWidth: fit) }
                        }
                    }
                }
                .padding(Self.inset)
            }
            .scrollPosition($position)
            .onScrollGeometryChange(for: CGRect.self) { $0.visibleRect } action: { _, new in visible = new }
            // Wheel, trackpad and momentum count as the user; programmatic scrolls are not in these phases.
            .onScrollPhaseChange { _, new in
                if new == .interacting || new == .decelerating { preview.userScrolled = true }
            }
            .onChange(of: preview.targetSerial) { reveal(fit: fit) }
            .onChange(of: preview.pageRequest.serial) { scrollToPage(preview.pageRequest.page, fit: fit) }
            .onChange(of: fit, initial: true) { preview.fitWidth = fit }
            .onChange(of: geo.size, initial: true) { preview.viewport = geo.size }
            .onScrollPhaseChange { _, phase in if phase == .interacting { jumped = nil } }   // the user's own scroll ends the jump
            .onChange(of: visible) { updateVisiblePage(fit: fit) }
            .onChange(of: preview.pages.count) { updateVisiblePage(fit: fit) }
        }
    }

    /// Scrolls only when the target is outside the visible rect, so typing in text that is already
    /// on screen never moves the preview. The y is computed from page sizes because lazy pages have no frame yet.
    private func reveal(fit: CGFloat) {
        guard let t = preview.target, preview.targetDecision.scrollIfOutside, preview.pages.indices.contains(t.page) else { return }
        let frame = frames(fit: fit)[t.page]
        let y = frame.minY + t.point.y * frame.width / preview.pages[t.page].size.width
        guard y < visible.minY || y > visible.maxY else { return }
        position.scrollTo(y: max(0, y - visible.height / 3))  
    }

    private func frames(fit: CGFloat) -> [CGRect] {
        PreviewMath.frames(sizes: preview.pages.map(\.size), width: fit * preview.zoom, inset: Self.inset, columns: preview.columns)
    }

    private func scrollToPage(_ page: Int, fit: CGFloat) {
        let f = frames(fit: fit)
        guard f.indices.contains(page) else { return }
        jumped = page
        preview.visiblePage = page
        position.scrollTo(y: max(0, f[page].minY - Self.inset))
    }

    private func updateVisiblePage(fit: CGFloat) {
        let f = frames(fit: fit)
        if let j = jumped, f.indices.contains(j), f[j].intersects(visible) { return }
        jumped = nil
        guard let p = PreviewMath.mostVisiblePage(frames: f, visible: visible), p != preview.visiblePage else { return }
        preview.visiblePage = p
    }
}

struct PageView: View {
    let page: PageInfo
    let project: Project
    let fitWidth: CGFloat
    @Environment(\.displayScale) private var displayScale
    @State private var markerOpacity = 0.0
    private var preview: PreviewModel { project.preview }

    var body: some View {
        let width = fitWidth * preview.zoom
        let scale = width / page.size.width
        let key = ImageKey(page.hash, pixelsPerPoint: displayScale * scale)
        PageImage(image: preview.image(for: key, index: page.id), dark: preview.darkPages)
        .aspectRatio(page.size, contentMode: .fit)
        .frame(width: width)
        .overlay(alignment: .topLeading) {
            if let t = preview.target, preview.targetDecision.marker, t.page == page.id {
                Circle()
                    .fill(Color.accentColor.opacity(0.3))
                    .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                    .frame(width: 24, height: 24)
                    .offset(x: t.point.x * scale - 12, y: t.point.y * scale - 12)
                    .opacity(markerOpacity)
                    .allowsHitTesting(false)
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
        .gesture(SpatialTapGesture().onEnded { tap in
            let point = CGPoint(x: tap.location.x / scale, y: tap.location.y / scale)
            Task { if let url = await project.click(page: page.id, at: point) { NSWorkspace.shared.open(url) } }
        })
        .accessibilityLabel("Page \(page.id + 1)")
        .task(id: key) { await preview.render(page, key) }
        .task(id: preview.targetSerial) { await flashMarker() }
    }

    /// Fresh navigation aims only: a page scrolled into view later must not replay an old one.
    private func flashMarker() async {
        markerOpacity = 0
        guard preview.targetDecision.marker, preview.target?.page == page.id,
              Date.now.timeIntervalSince(preview.targetDate) < 1.5 else { return }
        markerOpacity = 1
        try? await Task.sleep(for: .milliseconds(250))
        withAnimation(.easeOut(duration: 0.9)) { markerOpacity = 0 }
    }
}

/// A page's paper and its rendered image. A page is paper in dark mode too, unless the user asked for dark pages:
/// then it is inverted with the hue turned back, so white paper turns black and colors keep their hue.
struct PageImage: View {
    let image: CGImage?
    let dark: Bool

    var body: some View {
        ZStack {
            Color.white
            if let image {
                Image(decorative: image, scale: 1).resizable().interpolation(.high)
            }
        }
        .compositingGroup()
        .modifier(DarkPage(isOn: dark))
    }
}

private struct DarkPage: ViewModifier {
    let isOn: Bool
    func body(content: Content) -> some View {
        if isOn { content.colorInvert().hueRotation(.degrees(180)) } else { content }
    }
}

/// Shown while a failed compile leaves the last good render on screen.
private struct StaleBanner: View {
    var body: some View {
        Label("Showing the last valid version", systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular.tint(.orange.opacity(0.3)), in: .capsule)
            .padding(.bottom, 16)
            .help("The document has errors; the preview shows the last version that compiled.")
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// Small renders of every page beside the preview; a click scrolls the preview to that page.
private struct ThumbnailStrip: View {
    let project: Project
    private var preview: PreviewModel { project.preview }
    static let width: CGFloat = 96

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 10) {
                    ForEach(preview.pages) { page in
                        Button { preview.jump(toPage: page.id) } label: {
                            Thumbnail(page: page, preview: preview, selected: page.id == preview.visiblePage, width: Self.width)
                        }
                        .buttonStyle(.plain)
                        .id(page.id)
                    }
                }
                .padding(.vertical, 12)
            }
            .onChange(of: preview.visiblePage) { withAnimation { proxy.scrollTo(preview.visiblePage) } }
        }
        .frame(width: Self.width + 24)
    }
}

struct Thumbnail: View {
    let page: PageInfo
    let preview: PreviewModel
    let selected: Bool
    let width: CGFloat
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let key = ImageKey(page.hash, pixelsPerPoint: displayScale * width / page.size.width)
        VStack(spacing: 4) {
            PageImage(image: preview.image(for: key), dark: preview.darkPages)
                .aspectRatio(page.size, contentMode: .fit)
                .frame(width: width)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                .padding(3)
                .overlay { if selected { RoundedRectangle(cornerRadius: 4).stroke(Color.accentColor, lineWidth: 2) } }
            Text("\(page.id + 1)").font(.caption).monospacedDigit().foregroundStyle(selected ? .primary : .secondary)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(page.id + 1)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .task(id: key) { await preview.render(page, key, thumbnail: true) }
    }
}

/// Window identity of the presenter view that accompanies a presentation.
struct PresenterID: Hashable, Codable { let project: ProjectID }

/// Page and clock of one project's presentation, shared by the full-screen slides and the presenter view.
@MainActor @Observable final class PresentationSession {
    private static var sessions: [ProjectID: PresentationSession] = [:]

    let project: Project
    var show: SlideShow
    /// B or W blanks the slides black or white; the presenter view keeps showing them.
    var blank: Color?
    /// Presenter notes, filled in by the presenter view.
    var notes: [PresenterNote] = []
    /// The page the slides window has rendered ahead at full size, for the ready-to-advance indicator.
    var readyPage: Int?
    /// Set by `end`; the presenter view closes itself on it.
    private(set) var ended = false
    /// The screen the presentation was started from; the presenter view opens there.
    @ObservationIgnored var home: NSScreen?
    /// The presenter view's window number, for Swap Displays. A number, not a weak reference: the window reports
    /// itself while SwiftUI tears it down, and a weak reference to a window in deallocation traps.
    @ObservationIgnored var presenterWindow = 0
    @ObservationIgnored private var slides: NSWindow?
    @ObservationIgnored private var savedOptions: NSApplication.PresentationOptions = []
    @ObservationIgnored private var windows = 0

    private init(_ project: Project) {
        self.project = project
        show = SlideShow(page: project.preview.visiblePage)
    }

    static func session(for project: Project) -> PresentationSession {
        if let s = sessions[project.id] { return s }
        let s = PresentationSession(project)
        sessions[project.id] = s
        return s
    }

    /// Waits briefly for the project, like the pop-out preview, and counts the calling window until `detach`.
    static func attach(_ id: ProjectID) async -> PresentationSession? {
        for _ in 0..<30 {
            if let p = OpenProjects.shared.projects.first(where: { $0.id == id }) {
                let s = session(for: p)
                s.windows += 1
                return s
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    /// The last window to close discards the session, so the next presentation starts afresh.
    func detach() {
        windows -= 1
        if windows <= 0, Self.sessions[project.id] === self { Self.sessions[project.id] = nil }
    }

    static func discard(_ id: ProjectID) { sessions[id]?.end() }

    /// Shows the slides on `screen` in a borderless window that covers it from its first frame. Unlike native full
    /// screen there is no windowed frame, zoom animation or Space switch, so pages render once at their final size,
    /// and a presenter view on the same display stays visible.
    func showSlides(on screen: NSScreen, key: Bool) {
        if let slides { return slides.orderFront(nil) }
        let window = SlidesWindow(session: self, contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.title = String(localized: "Presentation – \(project.main.raw)")
        // On the menu bar's screen presentationOptions hide menu bar and Dock; elsewhere the window covers its menu bar.
        if screen != NSScreen.screens.first { window.level = .mainMenu + 1 }
        let host = NSHostingView(rootView: PresentationWindow(session: self))
        window.contentView = host
        window.setFrame(screen.frame, display: false)
        slides = window
        windows += 1
        window.alphaValue = 0
        if key { window.makeKeyAndOrderFront(nil) } else { window.orderFront(nil) }
        window.makeFirstResponder(host)
        savedOptions = NSApp.presentationOptions
        // A native full-screen window owns the options; they may not be changed under it.
        if !savedOptions.contains(.fullScreen) { NSApp.presentationOptions = [.hideDock, .hideMenuBar] }
        NSCursor.setHiddenUntilMouseMoves(true)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.2; window.animator().alphaValue = 1 }
    }

    /// Ends the presentation: closes the slides, and the presenter view through `ended`.
    func end() {
        if let slides {
            self.slides = nil
            slides.close()
            if !savedOptions.contains(.fullScreen) { NSApp.presentationOptions = savedOptions }
            detach()
        }
        ended = true
        if Self.sessions[project.id] === self { Self.sessions[project.id] = nil }
    }

    /// Keynote's Swap Displays (X): the slides go to the presenter view's display and the presenter view to theirs.
    func swapDisplays() {
        guard let slides, let presenter = NSApp.window(withWindowNumber: presenterWindow), let a = slides.screen, let b = presenter.screen, a != b else { return }
        slides.level = b != NSScreen.screens.first ? .mainMenu + 1 : .normal
        slides.setFrame(b.frame, display: true)
        let size = presenter.frame.size, area = a.visibleFrame
        presenter.setFrameOrigin(NSPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2))
        home = a
    }

    var showsSlides: Bool { slides != nil }
    var count: Int { project.preview.pages.count }
    var page: Int { show.current(count: count) }
    func move(_ delta: Int) { show.move(by: delta, count: count, at: .now) }
    func go(to page: Int) { show.go(to: page, count: count, at: .now) }
}

extension PresentationSession {
    /// Starts a presentation of `project`. As in Keynote, a second display gets the slides and this one the presenter
    /// view, also when `presenter` was not asked for. With one display, `presenter` shows the presenter view alone, as
    /// a rehearsal, because slides over it would hide the notes; otherwise the slides fill this display.
    static func start(_ project: Project, presenter: Bool, openWindow: OpenWindowAction) {
        let s = session(for: project)
        guard let home = NSApp.keyWindow?.screen ?? NSScreen.main else { return }
        s.home = home
        let other = NSScreen.screens.first(where: { $0 != home })
        let withPresenter = presenter || other != nil
        if withPresenter { openWindow(value: PresenterID(project: project.id)) }
        // With a presenter view the keys go to it; the slides only show.
        if let screen = withPresenter ? other : home { s.showSlides(on: screen, key: !withPresenter) }
    }
}

/// Borderless, yet takes key status so the slide keys reach it.
private final class SlidesWindow: NSWindow {
    private weak var session: PresentationSession?
    init(session: PresentationSession, contentRect: NSRect, styleMask: NSWindow.StyleMask, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        self.session = session
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    // Escape SwiftUI did not handle (its focus never took) must still end a presentation that hides the menu bar.
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { session?.end() } else { super.keyDown(with: event) }
    }
}

/// The keys of both presentation windows, Keynote's: arrows, space and page keys move, a number and Return go to
/// that slide, B and W blank the slides, R resets the timer, X swaps the displays, Escape ends.
struct SlideKeys: ViewModifier {
    let session: PresentationSession?
    /// Bumped by a view whose popover or overlay took the focus, to take it back.
    var refocus = 0
    @FocusState private var focused: Bool
    @State private var typed = ""

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onKeyPress(keys: [.rightArrow, .downArrow, .space, .pageDown]) { _ in session?.move(1); return .handled }
            .onKeyPress(keys: [.leftArrow, .upArrow, .pageUp]) { _ in session?.move(-1); return .handled }
            .onKeyPress(.home) { session?.go(to: 0); return .handled }
            .onKeyPress(.end) { session?.go(to: .max); return .handled }
            .onKeyPress(characters: CharacterSet(charactersIn: "bB.")) { _ in blank(.black) }
            .onKeyPress(characters: CharacterSet(charactersIn: "wW,")) { _ in blank(.white) }
            .onKeyPress(characters: CharacterSet(charactersIn: "rR")) { _ in session?.show.clock.reset(); return .handled }
            .onKeyPress(characters: .decimalDigits) { press in typed += press.characters; return .handled }
            .onKeyPress(.return) {
                guard let n = Int(typed) else { return .ignored }
                typed = ""
                session?.go(to: n - 1)
                return .handled
            }
            .onKeyPress(.delete) {
                guard !typed.isEmpty else { return .ignored }
                typed = ""
                return .handled
            }
            .onKeyPress(characters: CharacterSet(charactersIn: "xX")) { _ in session?.swapDisplays(); return .handled }
            .onKeyPress(.escape) { session?.end(); return .handled }
            .onChange(of: session != nil, initial: true) { _, ready in focused = ready }
            .onChange(of: session?.page) { typed = "" }
            .onChange(of: refocus) { focused = true }
            .overlay(alignment: .bottom) {
                if !typed.isEmpty {
                    Text("Go to Slide \(typed)")
                        .font(.title).monospacedDigit()
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .background(.black.opacity(0.8), in: .capsule)
                        .foregroundStyle(.white)
                        .padding(.bottom, 40)
                }
            }
    }

    private func blank(_ color: Color) -> KeyPress.Result {
        session?.blank = session?.blank == color ? nil : color
        return .handled
    }
}

/// One page at a time, full screen on black, for slides (Touying, Polylux). Arrow keys, space and a click
/// move through the pages; Escape ends the presentation.
struct PresentationWindow: View {
    let session: PresentationSession

    var body: some View {
        ZStack {
            session.blank ?? .black
            let pages = session.project.preview.pages, page = session.page
            if pages.indices.contains(page) {
                Slide(preview: session.project.preview, page: pages[page])
                    .opacity(session.blank == nil ? 1 : 0)
                    .onTapGesture { session.move(1) }
            }
            // The next page renders ahead so a key press shows it at once.
            if pages.indices.contains(page + 1) {
                Slide(preview: session.project.preview, page: pages[page + 1]) { session.readyPage = $0 }.hidden()
            }
        }
        .ignoresSafeArea()
        .modifier(SlideKeys(session: session))
    }
}

/// A page as large as fits the space it gets.
struct Slide: View {
    let preview: PreviewModel
    let page: PageInfo
    /// nil while the page renders, then its index.
    var rendered: ((Int?) -> Void)?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / page.size.width, geo.size.height / page.size.height)
            let key = ImageKey(page.hash, pixelsPerPoint: displayScale * scale)
            PageImage(image: preview.image(for: key, index: page.id), dark: preview.darkPages)
                .frame(width: page.size.width * scale, height: page.size.height * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Slide \(page.id + 1) of \(preview.pages.count)")
                .task(id: key) {
                    rendered?(nil)
                    await preview.render(page, key)
                    if !Task.isCancelled { rendered?(page.id) }
                }
        }
    }
}
