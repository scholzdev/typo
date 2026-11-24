internal import TypstBridge
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The only file that touches `Tb*` types.
public enum Bridge {
    static func withStr<R>(_ s: String, _ body: (TbStr) -> R) -> R {
        var s = s
        return s.withUTF8 { body(TbStr(ptr: $0.baseAddress, len: $0.count)) }
    }

    static func string(_ s: TbStr) -> String {
        guard let p = s.ptr else { return "" }
        return String(decoding: UnsafeBufferPointer(start: p, count: s.len), as: UTF8.self)
    }

    static func withStrs<R>(_ strings: [String], _ body: (UnsafeBufferPointer<TbStr>) -> R) -> R {
        var blob: [UInt8] = []
        var spans: [(Int, Int)] = []
        for p in strings {
            let u = Array(p.utf8)
            spans.append((blob.count, u.count))
            blob += u
        }
        return blob.withUnsafeBufferPointer { b in
            let strs = spans.map { (pos, len) in TbStr(ptr: b.baseAddress.map { $0 + pos }, len: len) }
            return strs.withUnsafeBufferPointer(body)
        }
    }

    static func makeRuntime(fontPaths: [String], indexPath: String, packageDir: String) -> OpaquePointer {
        withStrs(fontPaths) { sp in
            withStr(indexPath) { idx in withStr(packageDir) { pkg in
                tb_runtime_new(sp.baseAddress, sp.count, idx, pkg)!
            } }
        }
    }
}

extension Bridge {
    /// An empty path clears the data dir. Returns the number of local packages found there.
    static func setPackagesDir(_ runtime: OpaquePointer, path: String) -> Int {
        withStr(path) { tb_runtime_set_packages_dir(runtime, $0) }
    }

    static func setPackageIndex(_ runtime: OpaquePointer, json: Data) -> Int {
        json.withUnsafeBytes { b in
            tb_runtime_set_package_index(runtime, TbStr(ptr: b.baseAddress?.assumingMemoryBound(to: UInt8.self), len: b.count))
        }
    }
}

extension Bridge {
    /// JSON of the index's template packages (`[]` before any index).
    public static func templates(_ runtime: OpaquePointer) -> Data {
        let b = tb_runtime_templates(runtime)
        guard let p = b.ptr else { return Data() }
        defer { tb_bytes_free(b) }
        return Data(bytes: p, count: b.len)
    }

    /// Blocking (network). `ok`: `text` is the package directory, else an error message.
    public static func fetchPackage(_ runtime: OpaquePointer, spec: String) -> (ok: Bool, text: String) {
        var ok = false
        let b = withStr(spec) { tb_runtime_fetch_package(runtime, $0, &ok) }
        defer { tb_bytes_free(b) }
        return (ok, string(TbStr(ptr: b.ptr, len: b.len)))
    }
}

final class DownloadCallback {
    let fn: @Sendable (String) -> Void
    init(_ fn: @escaping @Sendable (String) -> Void) { self.fn = fn }
}

/// Owns a TbWorld. One thread at a time: the Engine's queue.
public final class WorldHandle: @unchecked Sendable {
    private let raw: OpaquePointer
    private let callback: Unmanaged<DownloadCallback>

    public init?(runtime: TypstRuntime, root: URL, main: RelPath, onDownload: @escaping @Sendable (String) -> Void) {
        let cb = Unmanaged.passRetained(DownloadCallback(onDownload))
        let w = Bridge.withStr(root.path) { r in
            Bridge.withStr(main.raw) { m in
                tb_world_new(runtime.handle, r, m, { ctx, spec in
                    Unmanaged<DownloadCallback>.fromOpaque(ctx!).takeUnretainedValue().fn(Bridge.string(spec))
                }, cb.toOpaque())
            }
        }
        guard let w else { cb.release(); return nil }
        raw = w
        callback = cb
    }

    deinit {
        tb_world_free(raw)
        callback.release()
    }

    func setMain(_ p: RelPath) { Bridge.withStr(p.raw) { tb_world_set_main(raw, $0) } }

    public func setProjectFonts(_ paths: [String]) { Bridge.withStrs(paths) { tb_world_set_project_fonts(raw, $0.baseAddress, $0.count) } }

    public func setText(_ p: RelPath, _ text: String) {
        Bridge.withStr(p.raw) { path in Bridge.withStr(text) { tb_world_set_text(raw, path, $0) } }
    }

    func relocateOverlay(_ old: RelPath, _ new: RelPath) {
        _ = Bridge.withStr(old.raw) { o in Bridge.withStr(new.raw) { tb_world_relocate_overlay(raw, o, $0) } }
    }

    func removeOverlay(_ p: RelPath) { Bridge.withStr(p.raw) { tb_world_remove_overlay(raw, $0) } }

    func edit(_ p: RelPath, _ range: NSRange, _ replacement: String, expectedLength: Int) -> Bool {
        Bridge.withStr(p.raw) { path in
            Bridge.withStr(replacement) { r in
                tb_world_edit(raw, path, UInt32(range.location), UInt32(NSMaxRange(range)), r, UInt32(expectedLength))
            }
        }
    }

    /// Test support: the overlay text the Rust side holds.
    func text(of p: RelPath) -> String? {
        let b = Bridge.withStr(p.raw) { tb_world_text(raw, $0) }
        guard let ptr = b.ptr else { return nil }
        defer { tb_bytes_free(b) }
        return String(decoding: UnsafeBufferPointer(start: ptr, count: b.len), as: UTF8.self)
    }

    /// `text` nil completes the file's overlay; otherwise `text` stands in for the file's content without being stored.
    func complete(_ p: RelPath, text: String? = nil, cursor: Int, explicit: Bool) -> (from: Int, items: [CompletionItem])? {
        let c = Bridge.withStr(p.raw) { path in
            guard let text else { return tb_world_complete(raw, path, UInt32(cursor), explicit) }
            return Bridge.withStr(text) { tb_world_complete_text(raw, path, $0, UInt32(cursor), explicit) }
        }
        guard let c else { return nil }
        defer { tb_completions_free(c) }
        let items = (0..<tb_completions_count(c)).map { i in
            let t = tb_completions_get(c, i)
            let kind: CompletionKind = switch t.kind {
            case 0: .syntax
            case 1: .function
            case 2: .type
            case 3: .parameter
            case 4: .constant
            case 5: .path
            case 6: .package
            case 7: .label
            case 8: .font
            default: .symbol(Bridge.string(t.symbol))
            }
            let apply = Bridge.string(t.apply), detail = Bridge.string(t.detail)
            return CompletionItem(kind: kind, label: Bridge.string(t.label),
                                  apply: apply.isEmpty ? nil : apply, detail: detail.isEmpty ? nil : detail)
        }
        return (Int(tb_completions_from(c)), items)
    }

    /// Resolves against `shown`, the document the user clicked on, and the world's current text.
    /// Nil target = nothing there (or a package file). The result's file is project-relative.
    public func jumpFromClick(shown: Snapshot, page: Int, point: CGPoint) -> JumpTarget? {
        guard let j = tb_world_jump_from_click(raw, shown.handle,
                                               TbPosition(page: UInt32(page), x_pt: Float(point.x), y_pt: Float(point.y))) else { return nil }
        defer { tb_jump_free(j) }
        switch Int(tb_jump_kind(j)) {
        case Int(TB_JUMP_FILE):
            guard let rel = RelPath(Bridge.string(tb_jump_path(j))) else { return nil }
            return .file(rel, Int(tb_jump_offset16(j)))
        case Int(TB_JUMP_URL):
            return URL(string: Bridge.string(tb_jump_url(j))).map { .url($0) }
        case Int(TB_JUMP_POSITION):
            return .position(Self.position(tb_jump_position(j)))
        default:
            return nil
        }
    }

    public func jumpFromCursor(_ p: RelPath, cursor: Int) -> [PreviewPosition] {
        var cap = 8
        while true {
            var buf = [TbPosition](repeating: TbPosition(page: 0, x_pt: 0, y_pt: 0), count: cap)
            let n = Bridge.withStr(p.raw) { path in
                buf.withUnsafeMutableBufferPointer { tb_world_jump_from_cursor(raw, path, UInt32(cursor), $0.baseAddress, cap) }
            }
            if n <= cap { return buf.prefix(n).map(Self.position) }
            cap = n
        }
    }

    /// The tooltip at `cursor`, nil if there is none.
    func hover(_ p: RelPath, cursor: Int) -> RawTooltip? {
        guard let h = Bridge.withStr(p.raw, { tb_world_hover(raw, $0, UInt32(cursor)) }) else { return nil }
        defer { tb_hover_free(h) }
        let r = tb_hover_range(h)
        return RawTooltip(isCode: Int(tb_hover_kind(h)) == Int(TB_HOVER_CODE), text: Bridge.string(tb_hover_text(h)),
                          range: NSRange(location: Int(r.start), length: Int(r.end - r.start)))
    }

    /// The definition of the item at `cursor`, nil if there is none.
    func definition(_ p: RelPath, cursor: Int) -> RawDefinition? {
        guard let d = Bridge.withStr(p.raw, { tb_world_definition(raw, $0, UInt32(cursor)) }) else { return nil }
        defer { tb_definition_free(d) }
        let r = tb_definition_range16(d)
        let kind: RawDefinition.Kind
        switch Int(tb_definition_kind(d)) {
        case Int(TB_DEF_SPAN): kind = .span
        case Int(TB_DEF_FILE): kind = .file
        case Int(TB_DEF_STD): kind = .std
        default: kind = .package
        }
        return RawDefinition(kind: kind, path: Bridge.string(tb_definition_path(d)), range: NSRange(location: Int(r.start), length: Int(r.end - r.start)), name: Bridge.string(tb_definition_name(d)),
                             docs: Bridge.string(tb_definition_docs(d)), url: Bridge.string(tb_definition_url(d)),
                             signature: Bridge.string(tb_definition_signature(d)))
    }

    /// Signature help for the call whose argument list holds `cursor`, nil outside one.
    func signatureHelp(_ p: RelPath, cursor: Int) -> SignatureHelp? {
        let b = Bridge.withStr(p.raw) { tb_world_signature_help(raw, $0, UInt32(cursor)) }
        defer { tb_bytes_free(b) }
        guard let ptr = b.ptr else { return nil }
        return try? JSONDecoder().decode(SignatureHelp.self, from: Data(bytes: ptr, count: b.len))
    }

    private static func position(_ p: TbPosition) -> PreviewPosition {
        PreviewPosition(page: Int(p.page), point: CGPoint(x: Double(p.x_pt), y: Double(p.y_pt)))
    }

    public func compile() -> Snapshot { Snapshot(tb_world_compile(raw)) }

    /// The compiled look of the equation around `cursor`, nil if there is none to show.
    func equationImage(_ p: RelPath, cursor: Int, pixelsPerPoint: Float) -> RawEquation? {
        var w: UInt32 = 0, h: UInt32 = 0, wpt: Float = 0, hpt: Float = 0
        var r = TbRange16(start: 0, end: 0)
        let bytes = Bridge.withStr(p.raw) { tb_world_equation_image(raw, $0, UInt32(cursor), pixelsPerPoint, &w, &h, &wpt, &hpt, &r) }
        guard let image = Bridge.image(bytes, width: w, height: h) else { return nil }
        return RawEquation(image: image, size: CGSize(width: Double(wpt), height: Double(hpt)),
                           range: NSRange(location: Int(r.start), length: Int(r.end - r.start)))
    }
}

extension Bridge {
    /// Zero copy: the provider's release callback frees the Rust buffer. Nil for an empty result.
    fileprivate static func image(_ bytes: TbBytes, width w: UInt32, height h: UInt32) -> CGImage? {
        guard let ptr = bytes.ptr else { return nil }
        let box = Unmanaged.passRetained(BytesBox(bytes))
        guard let provider = CGDataProvider(dataInfo: box.toOpaque(), data: ptr, size: bytes.len, releaseData: { info, _, _ in
            Unmanaged<BytesBox>.fromOpaque(info!).release()
        }) else { box.release(); return nil }
        return CGImage(width: Int(w), height: Int(h), bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: Int(w) * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

/// Only the TbBytes lives in the CGDataProvider's info, never the Snapshot: hash-keyed images outlive
/// many compiles, and each would otherwise pin a whole PagedDocument.
private final class BytesBox {
    let bytes: TbBytes
    init(_ b: TbBytes) { bytes = b }
    deinit { tb_bytes_free(bytes) }
}

/// Wraps TbSnapshot. Copies pages and diagnostics into Swift values at init and frees on deinit.
/// Rendering and PDF run on the global executor, concurrently with the next compile.
public final class Snapshot: @unchecked Sendable {      // handle immutable; TbSnapshot is Sync
    private struct PageMeta { let hash: UInt128; let size: CGSize }
    private let metas: [PageMeta]
    public let diagnostics: [Diagnostic]         // ranges valid at CompileResult.seq
    public let outline: [OutlineItem]            // offsets valid at CompileResult.seq; empty when the compile failed
    fileprivate let handle: OpaquePointer     // TbSnapshot*

    /// Derived, not stored: a stored [PageInfo] would make a retain cycle with PageInfo.snapshot.
    public var pages: [PageInfo] {
        metas.enumerated().map { PageInfo(id: $0, hash: $1.hash, size: $1.size, snapshot: self) }
    }
    public var pageCount: Int { metas.count }

    init(_ handle: OpaquePointer) {
        self.handle = handle
        metas = (0..<tb_snapshot_page_count(handle)).map { i in
            let p = tb_snapshot_page(handle, i)
            return PageMeta(hash: UInt128(p.hash_hi) << 64 | UInt128(p.hash_lo), size: CGSize(width: Double(p.width_pt), height: Double(p.height_pt)))
        }
        diagnostics = (0..<tb_snapshot_diagnostic_count(handle)).map { i in
            let d = tb_snapshot_diagnostic(handle, i)
            let path = Bridge.string(d.path)
            let origin: Diagnostic.Origin
            switch (Int(d.origin), RelPath(path)) {
            case (Int(TB_PROJECT), let rel?):
                origin = .project(Location(file: rel, range: NSRange(location: Int(d.utf16_start), length: Int(d.utf16_end - d.utf16_start))))
            case (Int(TB_PACKAGE), _): origin = .package(path)
            default: origin = .detached
            }
            let hints = Bridge.string(d.hints)
            return Diagnostic(id: Int(i), severity: d.severity == UInt8(TB_ERROR) ? .error : .warning,
                              message: Bridge.string(d.message), hints: hints.isEmpty ? [] : hints.components(separatedBy: "\n"),
                              origin: origin)
        }
        outline = (0..<tb_snapshot_outline_count(handle)).compactMap { i in
            let h = tb_snapshot_outline(handle, i)
            guard let file = RelPath(Bridge.string(h.path)) else { return nil }
            return OutlineItem(id: Int(i), level: Int(h.level), numbering: Bridge.string(h.numbering), title: Bridge.string(h.title),
                               page: Int(h.page), y: CGFloat(h.y_pt), file: file, offset: Int(h.utf16_offset))
        }
    }

    deinit { tb_snapshot_free(handle) }

    /// Zero copy: the provider's release callback frees the Rust buffer.
    @concurrent public func render(page: Int, pixelsPerPoint: Float) async -> CGImage? {
        var w: UInt32 = 0, h: UInt32 = 0
        return Bridge.image(tb_snapshot_render(handle, UInt32(page), pixelsPerPoint, &w, &h), width: w, height: h)
    }

    /// Words of all page text. Walks the whole document (~9 ms for 150 pages), so never on the compile path.
    @concurrent func words() async -> Int { Int(tb_snapshot_word_count(handle)) }

    /// `pages`: the pages to export; nil exports every page.
    @concurrent public func pdf(standard: PDFStandard, pages: [PageSpan]? = nil) async -> Result<Data, ProjectError> {
        var ok = false
        let flat = (pages ?? []).flatMap { [UInt32($0.first ?? 0), UInt32($0.last ?? 0)] }
        let b = flat.withUnsafeBufferPointer { tb_snapshot_export_pdf(handle, standard.rawValue, $0.baseAddress, flat.count / 2, &ok) }
        defer { tb_bytes_free(b) }
        let data = b.ptr.map { Data(bytes: $0, count: b.len) } ?? Data()
        return ok ? .success(data) : .failure(.exportFailed(String(decoding: data, as: UTF8.self)))
    }

    /// Nil for a bad page.
    @concurrent public func svg(page: Int) async -> Data? {
        let b = tb_snapshot_svg(handle, UInt32(page))
        guard let p = b.ptr else { return nil }
        defer { tb_bytes_free(b) }
        return Data(bytes: p, count: b.len)
    }

    @concurrent public func sectionWords() async -> [SectionWords] {
        let b = tb_snapshot_section_words(handle)
        defer { tb_bytes_free(b) }
        guard let p = b.ptr else { return [] }
        return (try? JSONDecoder().decode([SectionWords].self, from: Data(bytes: p, count: b.len))) ?? []
    }

    /// PNG of one page at `ppi` (pixels per inch, written as the file's DPI).
    @concurrent public func png(page: Int, ppi: Int) async -> Data? {
        guard let image = await render(page: page, pixelsPerPoint: Float(ppi) / 72) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImagePropertyDPIWidth: ppi, kCGImagePropertyDPIHeight: ppi] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    /// Kept for callers that only need the bytes of a plain PDF.
    @concurrent public func pdf() async -> Data? { try? await pdf(standard: .plain).get() }
}

/// Mirrors typst_syntax::Tag in declaration order (the bridge's tag_u8 match pins the numbers).
public enum SyntaxTag: UInt8, CaseIterable, Sendable {
    case comment, punctuation, escape, strong, emph, link, raw, label, ref, heading, listMarker, listTerm
    case mathDelimiter, mathOperator, mathGroupingParens, keyword, `operator`, number, string, function
    case interpolated, error
    /// Swift-side only (never from the bridge): the unit suffix of a number such as `cm` in `2cm`.
    case unit
    /// Swift-side only: a TODO, FIXME or XXX marker inside a comment.
    case todo
}

/// What the caret edits, from the syntax mirror: decides which delimiters auto-close.
public enum SyntaxMode: UInt8, Sendable { case markup, code, math, text }

/// A one-based, inclusive run of pages; a nil end is open ("5-" is page 5 to the last).
public struct PageSpan: Equatable, Sendable {
    public var first: Int?
    public var last: Int?
    public init(first: Int?, last: Int?) { self.first = first; self.last = last }
}

public struct SyntaxSpan: Equatable {
    public let range: NSRange
    public let tag: SyntaxTag
    public init(range: NSRange, tag: SyntaxTag) { self.range = range; self.tag = tag }
}

/// Wraps TbSyntax: a derived parse of one buffer's text, main actor only, fed by the storage delegate.
public final class SyntaxMirror {
    fileprivate let raw: OpaquePointer

    public init(_ text: String) { raw = Bridge.withStr(text) { tb_syntax_new($0)! } }
    deinit { tb_syntax_free(raw) }

    public func setText(_ text: String) { Bridge.withStr(text) { tb_syntax_set_text(raw, $0) } }

    /// The reparsed range of the new text, or nil if the edit was rejected (caller resets with `setText`).
    public func edit(_ range: NSRange, _ replacement: String, expectedLength: Int) -> NSRange? {
        var dirty = TbRange16(start: 0, end: 0)
        let ok = Bridge.withStr(replacement) {
            tb_syntax_edit(raw, UInt32(range.location), UInt32(NSMaxRange(range)), $0, UInt32(expectedLength), &dirty)
        }
        return ok ? NSRange(location: Int(dirty.start), length: Int(dirty.end - dirty.start)) : nil
    }

    public func spans(in r: NSRange) -> [SyntaxSpan] {
        var cap = 256
        while true {
            var buf = [TbSpan](repeating: TbSpan(start: 0, end: 0, tag: 0), count: cap)
            let n = buf.withUnsafeMutableBufferPointer {
                tb_syntax_highlight(raw, UInt32(r.location), UInt32(NSMaxRange(r)), $0.baseAddress, cap)
            }
            if n <= cap {
                return buf.prefix(n).compactMap { s in
                    SyntaxTag(rawValue: s.tag).map { SyntaxSpan(range: NSRange(location: Int(s.start), length: Int(s.end - s.start)), tag: $0) }
                }
            }
            cap = n
        }
    }

    /// The innermost strong (0), emph (1) or `#underline[..]` (2) node around `r`, nil if none.
    public func enclosing(kind: UInt8, _ r: NSRange) -> NSRange? {
        var out = TbRange16(start: 0, end: 0)
        guard tb_syntax_enclosing(raw, kind, UInt32(r.location), UInt32(NSMaxRange(r)), &out) else { return nil }
        return NSRange(location: Int(out.start), length: Int(out.end - out.start))
    }

    /// The innermost argument list around `pos` with at least `minTargets` arguments, and each argument's Tab target.
    public func args(at pos: Int, minTargets: Int) -> (whole: NSRange, targets: [NSRange])? {
        var cap = 32
        while true {
            var whole = TbRange16(start: 0, end: 0)
            var buf = [TbRange16](repeating: TbRange16(start: 0, end: 0), count: cap)
            let n = buf.withUnsafeMutableBufferPointer { tb_syntax_args(raw, UInt32(pos), UInt32(minTargets), &whole, $0.baseAddress, cap) }
            if n == 0 { return nil }
            if n <= cap {
                func ns(_ r: TbRange16) -> NSRange { NSRange(location: Int(r.start), length: Int(r.end - r.start)) }
                return (ns(whole), buf.prefix(n).map(ns))
            }
            cap = n
        }
    }

    public func mode(at pos: Int) -> SyntaxMode { SyntaxMode(rawValue: tb_syntax_mode(raw, UInt32(pos))) ?? .markup }

    public func prose(in r: NSRange) -> [NSRange] {
        var cap = 256
        while true {
            var buf = [TbRange16](repeating: TbRange16(start: 0, end: 0), count: cap)
            let n = buf.withUnsafeMutableBufferPointer {
                tb_syntax_prose(raw, UInt32(r.location), UInt32(NSMaxRange(r)), $0.baseAddress, cap)
            }
            if n <= cap { return buf.prefix(n).map { NSRange(location: Int($0.start), length: Int($0.end - $0.start)) } }
            cap = n
        }
    }
}

extension SyntaxMirror {
    /// The innermost `table(...)` / `grid(...)` call around `pos`, nil if the caret is in none.
    public func table(at pos: Int) -> RawTable? {
        guard let t = tb_syntax_table_at(raw, UInt32(pos)) else { return nil }
        defer { tb_table_free(t) }
        let r = tb_table_range(t)
        func arg(_ a: TbTableArg, items: [String] = []) -> RawTable.Arg {
            RawTable.Arg(name: Bridge.string(a.name), value: Bridge.string(a.value), shape: Int(a.shape), items: items)
        }
        func cell(_ c: TbTableCell) -> RawTable.Cell {
            RawTable.Cell(isContent: c.kind == 0, source: Bridge.string(c.source), inner: Bridge.string(c.inner))
        }
        let reason = Bridge.string(tb_table_unsupported(t))
        var out = RawTable(callee: Bridge.string(tb_table_callee(t)),
                           range: NSRange(location: Int(r.start), length: Int(r.end - r.start)),
                           unsupported: reason.isEmpty ? nil : reason)
        guard reason.isEmpty else { return out }
        out.args = (0..<tb_table_arg_count(t)).map { i in
            arg(tb_table_arg(t, i), items: (0..<tb_table_arg_item_count(t, i)).map { Bridge.string(tb_table_arg_item(t, i, $0)) })
        }
        if tb_table_has_header(t) {
            out.headerArgs = (0..<tb_table_header_arg_count(t)).map { arg(tb_table_header_arg(t, $0)) }
            out.header = (0..<tb_table_cell_count(t, true)).map { cell(tb_table_cell(t, true, $0)) }
        }
        out.cells = (0..<tb_table_cell_count(t, false)).map { cell(tb_table_cell(t, false, $0)) }
        return out
    }
}

extension Bridge {
    /// Thread-safe: the segmentation the compiled word count uses.
    public static func words(in text: String) -> Int { withStr(text) { Int(tb_text_word_count($0)) } }

    public static func symbols() -> [TypstSymbol] {
        (0..<tb_symbol_count()).map { i in
            let s = tb_symbol(i)
            return TypstSymbol(name: string(s.name), text: string(s.text), isEmoji: s.emoji)
        }
    }

    /// Thread-safe: touches no world.
    public static func bibliography(_ text: String, yaml: Bool) -> (entries: [BibEntry], error: String?) {
        let b = withStr(text) { tb_bibliography($0, yaml)! }
        defer { tb_bib_free(b) }
        let error = string(tb_bib_error(b))
        let entries = (0..<tb_bib_count(b)).map { i in
            let e = tb_bib_entry(b, i)
            return BibEntry(key: string(e.key), title: string(e.title), authors: string(e.authors),
                            year: e.has_year ? Int(e.year) : nil, kind: string(e.kind))
        }
        return (entries, error.isEmpty ? nil : error)
    }
}

extension Bridge {
    /// Thread-safe: definitions, uses and imports of one Typst file's text.
    public static func bindings(in text: String) -> RawBindings {
        let b = withStr(text) { tb_syntax_bindings($0) }
        defer { tb_bytes_free(b) }
        guard let p = b.ptr else { return RawBindings() }
        return (try? JSONDecoder().decode(RawBindings.self, from: Data(bytes: p, count: b.len))) ?? RawBindings()
    }
}

extension Bridge {
    /// Thread-safe: typstyle-formatted text for the whole file or the nodes around `range` (UTF-16); nil on error.
    public static func format(_ text: String, range: NSRange?, width: Int, indent: Int) -> (range: NSRange, text: String)? {
        struct Out: Decodable { var start: Int; var end: Int; var text: String }
        let r = range ?? NSRange(location: 0, length: 0)
        let b = withStr(text) { tb_format($0, UInt32(r.location), UInt32(NSMaxRange(r)), range == nil, UInt32(width), UInt32(indent)) }
        defer { tb_bytes_free(b) }
        guard let p = b.ptr, let o = try? JSONDecoder().decode(Out.self, from: Data(bytes: p, count: b.len)), o.end >= o.start else { return nil }
        return (NSRange(location: o.start, length: o.end - o.start), o.text)
    }
}
