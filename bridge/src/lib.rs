use std::any::Any;
use std::collections::HashMap;
use std::ffi::c_void;
use std::io::{self, Read};
use std::path::PathBuf;
use std::sync::{Arc, RwLock};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::UNIX_EPOCH;

use serde::{Deserialize, Serialize};
use typst::diag::{FileError, FileResult, Severity};
use typst::foundations::{Bytes, Datetime, Duration};
use typst::ecow::EcoString;
use typst::syntax::package::{PackageSpec, PackageVersion, VersionBound};
use typst::syntax::ast::{self, AstNode};
use typst::syntax::{FileId, LinkedNode, Lines, RootedPath, Side, Source, SyntaxKind, SyntaxNode, Tag, VirtualPath, VirtualRoot, highlight};
use typst::text::{Font, FontBook, FontInfo};
use typst::utils::LazyHash;
use typst::{Library, LibraryExt, World, WorldExt};
use typst_kit::datetime::Time;
use typst_kit::downloader::{Downloader, SystemDownloader};
use typst_kit::files::{FileLoader, FileStore, FsRoot};
use typst_kit::fonts::{FontPath, FontStore};
use typst_kit::packages::{FsPackages, SystemPackages, UniversePackages};
use typst::introspection::{Introspector, PagedPosition};
use typst::foundations::{NativeElement, Selector, StyleChain, Value};
use typst::layout::{Abs, Frame, FrameItem, Point};
use unicode_segmentation::UnicodeSegmentation;
use typst::model::HeadingElem;
use typst_ide::{CompletionKind, IdeWorld, Jump};
use typst_layout::PagedDocument;

#[repr(C)]
#[derive(Clone, Copy)]
pub struct TbStr {
    ptr: *const u8,
    len: usize,
}

#[repr(C)]
pub struct TbBytes {
    ptr: *mut u8,
    len: usize,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct TbPage {
    hash_hi: u64,
    hash_lo: u64,
    width_pt: f32,
    height_pt: f32,
}

#[repr(C)]
pub struct TbDiagnostic {
    severity: u8,
    origin: u8,
    path: TbStr,
    utf16_start: u32,
    utf16_end: u32,
    message: TbStr,
    hints: TbStr,
}

pub type TbDownloadFn = Option<unsafe extern "C" fn(ctx: *mut c_void, spec: TbStr)>;

const NULL_STR: TbStr = TbStr { ptr: std::ptr::null(), len: 0 };
const NULL_BYTES: TbBytes = TbBytes { ptr: std::ptr::null_mut(), len: 0 };

impl TbStr {
    fn of(s: &str) -> TbStr {
        TbStr { ptr: s.as_ptr(), len: s.len() }
    }
    unsafe fn get<'a>(self) -> Option<&'a str> {
        if self.ptr.is_null() {
            return if self.len == 0 { Some("") } else { None };
        }
        std::str::from_utf8(unsafe { std::slice::from_raw_parts(self.ptr, self.len) }).ok()
    }
}

fn to_bytes(v: Vec<u8>) -> TbBytes {
    let b = v.into_boxed_slice();
    let len = b.len();
    TbBytes { ptr: Box::into_raw(b) as *mut u8, len }
}

// ---- Runtime ----

#[derive(Serialize, Deserialize)]
struct IndexEntry {
    path: String,
    size: u64,
    mtime_ns: u128,
    faces: Vec<(u32, FontInfo)>,
}

type PackageList = Arc<[(PackageSpec, Option<EcoString>)]>;

pub struct TbRuntime {
    fonts: Arc<FontStore>,
    package_cache: PathBuf,
    packages: Arc<RwLock<PackageList>>,
    /// The user's packages data dir (`<ns>/<name>/<version>`), swapped as a whole; worlds read it at the start of a compile.
    data_dir: Arc<RwLock<Option<Arc<PathBuf>>>>,
    /// JSON array of the index's compatible template packages, built when the index is applied.
    templates: RwLock<Arc<[u8]>>,
}

fn index_entry(path: &str, cached: &mut HashMap<String, IndexEntry>) -> Option<IndexEntry> {
    let meta = std::fs::metadata(path).ok()?;
    let size = meta.len();
    let mtime_ns = meta.modified().ok()?.duration_since(UNIX_EPOCH).ok()?.as_nanos();
    if let Some(e) = cached.remove(path) {
        if e.size == size && e.mtime_ns == mtime_ns {
            return Some(e);
        }
    }
    let data = std::fs::read(path).ok()?;
    let faces = FontInfo::iter(&data).enumerate().map(|(i, f)| (i as u32, f)).collect();
    Some(IndexEntry { path: path.to_string(), size, mtime_ns, faces })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_runtime_new(
    font_paths: *const TbStr,
    count: usize,
    index_path: TbStr,
    package_cache_dir: TbStr,
) -> *mut TbRuntime {
    let (Some(index_path), Some(cache)) = (unsafe { index_path.get() }, unsafe { package_cache_dir.get() }) else {
        return std::ptr::null_mut();
    };
    let paths: Vec<&str> = if font_paths.is_null() {
        vec![]
    } else {
        unsafe { std::slice::from_raw_parts(font_paths, count) }
            .iter()
            .filter_map(|p| unsafe { p.get() })
            .collect()
    };
    // A corrupt or missing index just means a full re-read.
    let mut cached: HashMap<String, IndexEntry> = std::fs::read(index_path)
        .ok()
        .and_then(|d| serde_json::from_slice::<Vec<IndexEntry>>(&d).ok())
        .unwrap_or_default()
        .into_iter()
        .map(|e| (e.path.clone(), e))
        .collect();

    let mut entries = Vec::new();
    for p in paths {
        if let Some(e) = index_entry(p, &mut cached) {
            entries.push(e);
        }
    }
    if let Ok(json) = serde_json::to_vec(&entries) {
        let tmp = format!("{index_path}.tmp");
        if let Some(dir) = std::path::Path::new(index_path).parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        if std::fs::write(&tmp, json).is_ok() {
            let _ = std::fs::rename(&tmp, index_path);
        }
    }

    let mut fonts = FontStore::new();
    fonts.extend(typst_kit::fonts::embedded());
    for e in entries {
        for (index, info) in e.faces {
            fonts.push((FontPath { path: PathBuf::from(&e.path), index }, info));
        }
    }
    let _ = std::fs::create_dir_all(cache);
    Box::into_raw(Box::new(TbRuntime { fonts: Arc::new(fonts), package_cache: PathBuf::from(cache), packages: Arc::default(), data_dir: Arc::default(), templates: RwLock::new(Arc::from(&b"[]"[..])) }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_runtime_free(r: *mut TbRuntime) {
    if !r.is_null() {
        drop(unsafe { Box::from_raw(r) });
    }
}

#[derive(Deserialize)]
struct IndexPackage {
    name: String,
    version: PackageVersion,
    description: Option<String>,
    compiler: Option<VersionBound>,
    // Raw values: a malformed field here must not drop the entry from the package list.
    authors: Option<serde_json::Value>,
    categories: Option<serde_json::Value>,
    template: Option<serde_json::Value>,
}

impl IndexPackage {
    fn compatible(&self) -> bool {
        self.compiler.is_none_or(|req| PackageVersion::compiler().matches_ge(&req))
    }

    /// The `tb_runtime_templates` element, nil without a usable `template` object.
    fn template_json(&self) -> Option<serde_json::Value> {
        let t = self.template.as_ref()?.as_object()?;
        let field = |k: &str| t.get(k).and_then(|v| v.as_str()).map(str::to_owned);
        let strings = |v: &Option<serde_json::Value>| -> Vec<String> {
            v.as_ref().and_then(|v| v.as_array()).into_iter().flatten().filter_map(|s| s.as_str().map(str::to_owned)).collect()
        };
        Some(serde_json::json!({
            "name": self.name, "version": self.version.to_string(),
            "description": self.description.clone().unwrap_or_default(),
            "authors": strings(&self.authors), "categories": strings(&self.categories),
            "path": field("path")?, "entrypoint": field("entrypoint")?,
        }))
    }
}

/// Replaces the `@preview` package list from the official index JSON. Returns how many entries were
/// kept (0 if the JSON is not an array). Entries that fail to parse or need a newer compiler are dropped.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_runtime_set_package_index(rt: *const TbRuntime, json: TbStr) -> usize {
    let rt = unsafe { &*rt };
    let Some(Ok(values)) = unsafe { json.get() }.map(serde_json::from_str::<Vec<serde_json::Value>>) else {
        return 0;
    };
    let kept: Vec<IndexPackage> = values
        .into_iter()
        .filter_map(|v| IndexPackage::deserialize(v).ok())
        .filter(IndexPackage::compatible)
        .collect();
    let mut latest: HashMap<&str, &IndexPackage> = HashMap::new();
    for p in kept.iter().filter(|p| p.template_json().is_some()) {
        if latest.get(p.name.as_str()).is_none_or(|q| q.version < p.version) {
            latest.insert(&p.name, p);
        }
    }
    let mut templates: Vec<_> = latest.into_values().filter_map(|p| p.template_json()).collect();
    templates.sort_by(|a, b| a["name"].as_str().cmp(&b["name"].as_str()));
    let templates = serde_json::to_vec(&templates).unwrap_or_else(|_| b"[]".to_vec());
    let list: PackageList = kept
        .into_iter()
        .map(|p| {
            let spec = PackageSpec { namespace: "preview".into(), name: p.name.into(), version: p.version };
            (spec, p.description.map(EcoString::from))
        })
        .collect();
    let n = list.len();
    *rt.packages.write().unwrap_or_else(|e| e.into_inner()) = list;
    *rt.templates.write().unwrap_or_else(|e| e.into_inner()) = Arc::from(templates);
    n
}

/// JSON array of the Universe template packages of the last applied index (see the header).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_runtime_templates(rt: *const TbRuntime) -> TbBytes {
    let rt = unsafe { &*rt };
    to_bytes(rt.templates.read().unwrap_or_else(|e| e.into_inner()).to_vec())
}

/// Resolves `spec` like a world does (data dir, cache, then Universe download into the cache).
/// `*ok` true: the bytes are the package directory; false: they are an error message.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_runtime_fetch_package(rt: *const TbRuntime, spec: TbStr, ok: *mut bool) -> TbBytes {
    let rt = unsafe { &*rt };
    let result = (|| -> Result<String, String> {
        let spec = unsafe { spec.get() }.ok_or("invalid package spec")?;
        let spec: PackageSpec = spec.parse().map_err(|e| format!("{e}"))?;
        let data = rt.data_dir.read().unwrap_or_else(|e| e.into_inner()).as_deref().cloned().map(FsPackages::new);
        let packages = SystemPackages::from_parts(
            data,
            Some(FsPackages::new(rt.package_cache.clone())),
            UniversePackages::with_url(SystemDownloader::new("tympan/0.1"), "https://packages.typst.org"),
        );
        let root = packages.obtain(&spec).map_err(|e| format!("{e}"))?;
        root.path().to_str().map(str::to_owned).ok_or_else(|| "package path is not UTF-8".to_string())
    })();
    unsafe { *ok = result.is_ok() };
    to_bytes(match result {
        Ok(s) => s,
        Err(e) if e.is_empty() => "package unavailable".into(),
        Err(e) => e,
    }.into_bytes())
}

#[derive(Deserialize)]
struct LocalManifest {
    package: LocalInfo,
}

#[derive(Deserialize)]
struct LocalInfo {
    description: Option<String>,
    compiler: Option<VersionBound>,
}

/// Lists `<dir>/<namespace>/<name>/<version>/typst.toml` entries. Unreadable or malformed manifests and
/// ones that need a newer compiler are skipped. The names come from the folders, as typst resolves them.
fn scan_local(dir: &std::path::Path) -> Vec<(PackageSpec, Option<EcoString>)> {
    let subdirs = |p: &std::path::Path| -> Vec<(String, PathBuf)> {
        std::fs::read_dir(p)
            .into_iter()
            .flatten()
            .flatten()
            .filter(|e| e.file_type().is_ok_and(|t| t.is_dir()))
            .filter_map(|e| Some((e.file_name().into_string().ok()?, e.path())))
            .collect()
    };
    let current = PackageVersion::compiler();
    let mut out = Vec::new();
    for (namespace, nsp) in subdirs(dir) {
        for (name, np) in subdirs(&nsp) {
            for (version, vp) in subdirs(&np) {
                let Ok(version) = version.parse::<PackageVersion>() else { continue };
                let Some(m) = std::fs::read_to_string(vp.join("typst.toml"))
                    .ok()
                    .and_then(|t| toml::from_str::<LocalManifest>(&t).ok())
                else {
                    continue;
                };
                if m.package.compiler.is_some_and(|req| !current.matches_ge(&req)) {
                    continue;
                }
                let spec = PackageSpec { namespace: namespace.as_str().into(), name: name.as_str().into(), version };
                out.push((spec, m.package.description.map(EcoString::from)));
            }
        }
    }
    out
}

/// Sets the packages data dir (empty string clears it). Worlds pick it up at the start of their next
/// compile or completion. Returns the number of compatible local packages found there now.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_runtime_set_packages_dir(rt: *const TbRuntime, dir: TbStr) -> usize {
    let rt = unsafe { &*rt };
    let dir = unsafe { dir.get() }.filter(|d| !d.is_empty()).map(|d| Arc::new(PathBuf::from(d)));
    let n = dir.as_ref().map_or(0, |d| scan_local(d).len());
    *rt.data_dir.write().unwrap_or_else(|e| e.into_inner()) = dir;
    n
}

// ---- World ----

struct CallbackDownloader {
    inner: SystemDownloader,
    on_download: TbDownloadFn,
    ctx: *mut c_void,
}
// The callback contract: it is invoked on the compiling thread only, and ctx outlives the world.
unsafe impl Send for CallbackDownloader {}
unsafe impl Sync for CallbackDownloader {}

impl Downloader for CallbackDownloader {
    fn stream(&self, key: &dyn Any, url: &str) -> io::Result<(Option<usize>, Box<dyn Read>)> {
        if let (Some(f), Some(spec)) = (self.on_download, key.downcast_ref::<PackageSpec>()) {
            let s = spec.to_string();
            unsafe { f(self.ctx, TbStr::of(&s)) };
        }
        self.inner.stream(key, url)
    }
}

struct Loader {
    project: FsRoot,
    /// The user's data dir, tried before the cache and the download (SystemPackages' own order).
    data: Option<FsPackages>,
    packages: SystemPackages,
}

impl FileLoader for Loader {
    fn load(&self, id: FileId) -> FileResult<Bytes> {
        let root = match id.root() {
            VirtualRoot::Project => self.project.clone(),
            VirtualRoot::Package(spec) => match self.data.as_ref().and_then(|d| d.obtain(spec)) {
                Some(root) => root,
                None => self.packages.obtain(spec)?,
            },
        };
        root.load(id.vpath())
    }
}

pub struct TbWorld {
    library: LazyHash<Library>,
    fonts: Arc<FontStore>,
    /// The project's own font files; their faces come first in `book`, so they win a family-name tie like `typst --font-path`.
    project_fonts: Vec<Font>,
    /// Project faces then the runtime's; None while the project has no fonts.
    book: Option<LazyHash<FontBook>>,
    files: FileStore<Loader>,
    time: Time,
    main: FileId,
    overlays: HashMap<FileId, Source>,
    root: PathBuf,
    /// Document of the last successful compile; label and citation completions read it.
    last_doc: Option<PagedDocument>,
    /// Hash of every overlay's text at that compile; an equation crop is only valid while the hovered text still matches.
    compiled_text: HashMap<FileId, u128>,
    shared_packages: Arc<RwLock<PackageList>>,
    shared_data_dir: Arc<RwLock<Option<Arc<PathBuf>>>>,
    data_dir: Option<Arc<PathBuf>>,
    /// Clone of `shared_packages` taken at the start of each completion request.
    packages: PackageList,
}

impl TbWorld {
    /// Takes the runtime's current data dir; called at the start of every compile and completion.
    fn refresh_data_dir(&mut self) {
        let current = self.shared_data_dir.read().unwrap_or_else(|e| e.into_inner()).clone();
        if current != self.data_dir {
            self.files.loader_mut().data = current.as_ref().map(|d| FsPackages::new(d.as_ref().clone()));
            self.data_dir = current;
        }
    }
}

impl World for TbWorld {
    fn library(&self) -> &LazyHash<Library> {
        &self.library
    }
    fn book(&self) -> &LazyHash<FontBook> {
        self.book.as_ref().unwrap_or_else(|| self.fonts.book())
    }
    fn main(&self) -> FileId {
        self.main
    }
    fn source(&self, id: FileId) -> FileResult<Source> {
        match self.overlays.get(&id) {
            Some(s) => Ok(s.clone()),
            None => self.files.source(id),
        }
    }
    fn file(&self, id: FileId) -> FileResult<Bytes> {
        match self.overlays.get(&id) {
            Some(s) => Ok(Bytes::from_string(s.text().to_string())),
            None => self.files.file(id),
        }
    }
    fn font(&self, index: usize) -> Option<Font> {
        match index.checked_sub(self.project_fonts.len()) {
            None => self.project_fonts.get(index).cloned(),
            Some(i) => self.fonts.font(i),
        }
    }
    fn today(&self, offset: Option<Duration>) -> Option<Datetime> {
        self.time.today(offset)
    }
}

impl IdeWorld for TbWorld {
    fn upcast(&self) -> &dyn World {
        self
    }
    fn packages(&self) -> &[(PackageSpec, Option<EcoString>)] {
        &self.packages
    }
    // shortcut: rescanned per request, capped at 5000 entries; upgrade to a cached tree when projects get large.
    fn files(&self) -> Vec<FileId> {
        const CAP: usize = 5000;
        let mut out = Vec::new();
        let mut stack = vec![(self.root.clone(), String::new())];
        while let Some((dir, prefix)) = stack.pop() {
            let Ok(rd) = std::fs::read_dir(&dir) else { continue };
            for entry in rd.flatten() {
                let name = entry.file_name().to_string_lossy().into_owned();
                if name.starts_with('.') {
                    continue;
                }
                let rel = format!("{prefix}{name}");
                match entry.file_type() {
                    Ok(t) if t.is_dir() => stack.push((entry.path(), format!("{rel}/"))),
                    Ok(t) if t.is_file() => {
                        if let Some(id) = project_id(&rel) {
                            out.push(id);
                        }
                    }
                    _ => {}
                }
                if out.len() >= CAP {
                    return out;
                }
            }
        }
        out
    }
}

static LIVE_WORLDS: AtomicUsize = AtomicUsize::new(0);

fn project_id(path: &str) -> Option<FileId> {
    let vpath = VirtualPath::new(path).ok()?;
    Some(RootedPath::new(VirtualRoot::Project, vpath).intern())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_world_new(
    rt: *const TbRuntime,
    root: TbStr,
    main: TbStr,
    on_download: TbDownloadFn,
    ctx: *mut c_void,
) -> *mut TbWorld {
    let (Some(root), Some(main)) = (unsafe { root.get() }, unsafe { main.get() }) else {
        return std::ptr::null_mut();
    };
    let Some(main) = project_id(main) else { return std::ptr::null_mut() };
    let rt = unsafe { &*rt };
    let downloader = CallbackDownloader { inner: SystemDownloader::new("tympan/0.1"), on_download, ctx };
    let packages = SystemPackages::from_parts(
        None,
        Some(FsPackages::new(rt.package_cache.clone())),
        UniversePackages::with_url(downloader, "https://packages.typst.org"),
    );
    LIVE_WORLDS.fetch_add(1, Ordering::SeqCst);
    Box::into_raw(Box::new(TbWorld {
        library: LazyHash::new(Library::default()),
        fonts: rt.fonts.clone(),
        project_fonts: Vec::new(),
        book: None,
        files: FileStore::new(Loader { project: FsRoot::new(PathBuf::from(root)), data: None, packages }),
        time: Time::system(),
        main,
        overlays: HashMap::new(),
        root: PathBuf::from(root),
        last_doc: None,
        compiled_text: HashMap::new(),
        shared_packages: rt.packages.clone(),
        shared_data_dir: rt.data_dir.clone(),
        data_dir: None,
        packages: rt.packages.read().unwrap_or_else(|e| e.into_inner()).clone(),
    }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_world_free(w: *mut TbWorld) {
    if !w.is_null() {
        drop(unsafe { Box::from_raw(w) });
        LIVE_WORLDS.fetch_sub(1, Ordering::SeqCst);
    }
}

/// Replaces the project's font files (absolute paths). Unreadable files and formats Typst cannot parse (WOFF) add no faces.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_world_set_project_fonts(w: *mut TbWorld, paths: *const TbStr, count: usize) {
    let w = unsafe { &mut *w };
    let paths: &[TbStr] = if paths.is_null() { &[] } else { unsafe { std::slice::from_raw_parts(paths, count) } };
    w.project_fonts = paths
        .iter()
        .filter_map(|p| unsafe { p.get() })
        .filter_map(|p| std::fs::read(p).ok())
        .flat_map(|data| Font::iter(Bytes::new(data)))
        .collect();
    w.book = (!w.project_fonts.is_empty()).then(|| {
        let system = w.fonts.book();
        let infos = w.project_fonts.iter().map(|f| f.info().clone());
        LazyHash::new(FontBook::from_infos(infos.chain((0..).map_while(|i| system.info(i).cloned()))))
    });
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_world_set_main(w: *mut TbWorld, path: TbStr) {
    let w = unsafe { &mut *w };
    if let Some(id) = unsafe { path.get() }.and_then(project_id) {
        w.main = id;
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_world_set_text(w: *mut TbWorld, path: TbStr, text: TbStr) {
    let w = unsafe { &mut *w };
    let (Some(id), Some(text)) = (unsafe { path.get() }.and_then(project_id), unsafe { text.get() }) else { return };
    match w.overlays.get_mut(&id) {
        Some(src) => {
            src.replace(text);
        }
        None => {
            w.overlays.insert(id, Source::new(id, text.to_string()));
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_world_edit(
    w: *mut TbWorld,
    path: TbStr,
    start: u32,
    end: u32,
    replacement: TbStr,
    expected_len: u32,
) -> bool {
    let w = unsafe { &mut *w };
    let (Some(id), Some(repl)) = (unsafe { path.get() }.and_then(project_id), unsafe { replacement.get() }) else {
        return false;
    };
    let Some(src) = w.overlays.get_mut(&id) else { return false };
    let Some(range) = checked_edit(src.lines(), start, end, repl, expected_len) else { return false };
    src.edit(range, repl);
    true
}

/// Validates a UTF-16 edit against the pre-edit text: bounds, scalar splits, and the post-edit length.
/// Returns the byte range to replace.
fn checked_edit(lines: &Lines<String>, start: u32, end: u32, repl: &str, expected_len: u32) -> Option<std::ops::Range<usize>> {
    let (start, end) = (start as usize, end as usize);
    // utf16_to_byte rounds a mid-surrogate index up to the next scalar, so round-trip to detect splits.
    let byte = |u: usize| lines.utf16_to_byte(u).filter(|&b| lines.byte_to_utf16(b) == Some(u));
    let (a, b) = (byte(start)?, byte(end)?);
    if a > b {
        return None;
    }
    let post = lines.len_utf16() - (end - start) + repl.encode_utf16().count();
    (post == expected_len as usize).then_some(a..b)
}

/// Moves one overlay to a new path with the same text. Returns false (and changes nothing) if `old` has no
/// overlay or either path is not a valid vpath. The file store is reset by the next compile.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_world_relocate_overlay(w: *mut TbWorld, old: TbStr, new: TbStr) -> bool {
    let w = unsafe { &mut *w };
    let (Some(old), Some(new)) = (unsafe { old.get() }.and_then(project_id), unsafe { new.get() }.and_then(project_id)) else {
        return false;
    };
    let Some(src) = w.overlays.remove(&old) else { return false };
    w.overlays.insert(new, Source::new(new, src.text().to_string()));
    true
}

/// Drops an overlay, so the next compile reads that path from disk again. No-op without an overlay.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_world_remove_overlay(w: *mut TbWorld, path: TbStr) {
    let w = unsafe { &mut *w };
    if let Some(id) = unsafe { path.get() }.and_then(project_id) {
        w.overlays.remove(&id);
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_world_text(w: *const TbWorld, path: TbStr) -> TbBytes {
    let w = unsafe { &*w };
    match unsafe { path.get() }.and_then(project_id).and_then(|id| w.overlays.get(&id)) {
        Some(s) => to_bytes(s.text().as_bytes().to_vec()),
        None => NULL_BYTES,
    }
}

// ---- Snapshot ----

struct OwnedDiag {
    severity: u8,
    origin: u8,
    path: String,
    start: u32,
    end: u32,
    message: String,
    hints: String,
}

struct OwnedHeading {
    level: u32,
    numbering: String,
    title: String,
    page: u32,
    y_pt: f32,
    path: String,
    offset16: u32,
}

pub struct TbSnapshot {
    doc: Option<PagedDocument>,
    pages: Vec<TbPage>,
    diags: Vec<OwnedDiag>,
    outline: Vec<OwnedHeading>,
}

/// Calls `f(page, x, y, item)` for every text item in document order, with group translations applied.
/// shortcut: group transforms are applied as translations only.
fn for_each_text(doc: &PagedDocument, mut f: impl FnMut(usize, f64, f64, &typst::text::TextItem)) {
    fn walk(fr: &Frame, ox: f64, oy: f64, page: usize, f: &mut impl FnMut(usize, f64, f64, &typst::text::TextItem)) {
        for (p, item) in fr.items() {
            match item {
                FrameItem::Group(g) => walk(&g.frame, ox + p.x.to_pt() + g.transform.tx.to_pt(), oy + p.y.to_pt() + g.transform.ty.to_pt(), page, f),
                FrameItem::Text(t) => f(page, ox + p.x.to_pt(), oy + p.y.to_pt(), t),
                _ => {}
            }
        }
    }
    for (i, page) in doc.pages().iter().enumerate() {
        walk(&page.frame, 0.0, 0.0, i, &mut f);
    }
}

/// Appends `t` to `out`, with a space first when it does not continue the previous item's line.
fn push_text(out: &mut String, last: &mut Option<(f64, f64)>, x: f64, y: f64, t: &typst::text::TextItem) {
    if last.is_some_and(|(ex, ey)| (y - ey).abs() > 0.5 || (x - ex).abs() > 1.0) {
        out.push(' ');
    }
    out.push_str(&t.text);
    *last = Some((x + t.width().to_pt(), y));
}

/// Words of the text of every page, by Unicode word segmentation. Items on one line are joined without a
/// separator unless there is a gap, so a word split across styled runs stays one word.
/// shortcut: hyphenated line breaks count as two words.
fn document_words(doc: &PagedDocument) -> u32 {
    let mut text = String::new();
    let mut last = None;
    let mut page = 0;
    for_each_text(doc, |p, x, y, t| {
        if p != page {
            text.push(' ');
            page = p;
        }
        push_text(&mut text, &mut last, x, y, t);
    });
    text.unicode_words().count() as u32
}

#[derive(Serialize)]
struct SectionWords {
    title: String,
    level: u32,
    words: u32,
    page: u32,
}

/// Words per heading section of the compiled document (any file), counted like `document_words`: a text item
/// belongs to the last heading at or before its (page, y). Entry 0 is the text before the first heading.
fn section_words(doc: &PagedDocument) -> Vec<SectionWords> {
    let selector = Selector::Elem(HeadingElem::ELEM, None);
    let mut heads: Vec<(usize, f64, SectionWords)> = doc
        .introspector()
        .query(&selector)
        .iter()
        .filter_map(|c| {
            let h = c.to_packed::<HeadingElem>()?;
            let pos = doc.introspector().position(h.location()?)?;
            let page = pos.page.get() - 1;
            Some((page, pos.point.y.to_pt(), SectionWords {
                title: h.body.plain_text().trim().to_string(),
                level: h.resolve_level(StyleChain::default()).get() as u32,
                words: 0,
                page: page as u32,
            }))
        })
        .collect();
    heads.sort_by(|a, b| (a.0, a.1).partial_cmp(&(b.0, b.1)).unwrap_or(std::cmp::Ordering::Equal));
    let keys: Vec<(usize, f64)> = heads.iter().map(|h| (h.0, h.1)).collect();
    let mut texts = vec![String::new(); heads.len() + 1];
    let mut last = None;
    for_each_text(doc, |p, x, y, t| {
        let i = keys.partition_point(|k| (k.0, k.1) <= (p, y));
        push_text(&mut texts[i], &mut last, x, y, t);
    });
    let mut out = vec![SectionWords { title: String::new(), level: 0, words: 0, page: 0 }];
    out.extend(heads.into_iter().map(|h| h.2));
    for (o, t) in out.iter_mut().zip(texts) {
        o.words = t.unicode_words().count() as u32;
    }
    out
}

/// Headings of `doc` that live in a project file, in document order. Offsets are in the world's text at compile time.
fn outline_of(world: &TbWorld, doc: &PagedDocument) -> Vec<OwnedHeading> {
    let selector = Selector::Elem(HeadingElem::ELEM, None);
    doc.introspector()
        .query(&selector)
        .iter()
        .filter_map(|c| {
            let h = c.to_packed::<HeadingElem>()?;
            let id = h.span().id().filter(|id| matches!(id.root(), VirtualRoot::Project))?;
            let range = world.range(h.span())?;
            let offset16 = world.source(id).ok()?.lines().byte_to_utf16(range.start)? as u32;
            let pos = doc.introspector().position(h.location()?)?;
            Some(OwnedHeading {
                level: h.resolve_level(StyleChain::default()).get() as u32,
                numbering: h.numbers.clone().map(|n| n.to_string()).unwrap_or_default(),
                title: h.body.plain_text().trim().to_string(),
                page: (pos.page.get() - 1) as u32,
                y_pt: pos.point.y.to_pt() as f32,
                path: id.vpath().get_without_slash().to_string(),
                offset16,
            })
        })
        .collect()
}

fn diagnose(world: &TbWorld, d: &typst::diag::SourceDiagnostic) -> OwnedDiag {
    let mut o = OwnedDiag {
        severity: if d.severity == Severity::Error { 0 } else { 1 },
        origin: 0,
        path: String::new(),
        start: 0,
        end: 0,
        message: d.message.to_string(),
        hints: d.hints.iter().map(|h| h.v.as_str()).collect::<Vec<_>>().join("\n"),
    };
    let Some(id) = d.span.id() else { return o };
    let (Some(range), Ok(src)) = (world.range(d.span), world.source(id)) else { return o };
    let lines = src.lines();
    o.start = lines.byte_to_utf16(range.start).unwrap_or(0) as u32;
    o.end = lines.byte_to_utf16(range.end).unwrap_or(0) as u32;
    let rel = id.vpath().get_without_slash();
    match id.root() {
        VirtualRoot::Project => {
            o.origin = 1;
            o.path = rel.to_string();
        }
        VirtualRoot::Package(spec) => {
            o.origin = 2;
            o.path = format!("{spec}/{rel}");
        }
    }
    o
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_world_compile(w: *mut TbWorld) -> *mut TbSnapshot {
    let w = unsafe { &mut *w };
    w.refresh_data_dir();
    w.files.reset();
    w.time.reset();
    // The caller is a GCD thread (512 KB stack) and layout recursion is not stack-guarded.
    let snap = stacker::grow(32 << 20, || {
        let typst::diag::Warned { output, warnings } = typst::compile::<PagedDocument>(&*w);
        let (doc, errors) = match output {
            Ok(d) => (Some(d), Default::default()),
            Err(e) => (None, e),
        };
        let pages = doc
            .iter()
            .flat_map(|d| d.pages())
            .map(|p| {
                let h = typst::utils::hash128(p);
                let s = p.frame.size();
                TbPage { hash_hi: (h >> 64) as u64, hash_lo: h as u64, width_pt: s.x.to_pt() as f32, height_pt: s.y.to_pt() as f32 }
            })
            .collect();
        let diags = errors.iter().chain(warnings.iter()).map(|d| diagnose(w, d)).collect();
        let outline = doc.as_ref().map(|d| outline_of(w, d)).unwrap_or_default();
        TbSnapshot { doc, pages, diags, outline }
    });
    if snap.doc.is_some() {
        w.last_doc = snap.doc.clone();
        w.compiled_text = w.overlays.iter().map(|(id, s)| (*id, typst::utils::hash128(s.text()))).collect();
    }
    // Each world's entries survive about 10 of its own compiles while windows take turns.
    typst::comemo::evict(10 * LIVE_WORLDS.load(Ordering::SeqCst).max(1));
    Box::into_raw(Box::new(snap))
}

/// Words of the compiled document (0 if the compile failed). Computed per call, off the compile path;
/// the snapshot is immutable, so any thread may call it.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_snapshot_word_count(s: *const TbSnapshot) -> u32 {
    unsafe { &*s }.doc.as_ref().map_or(0, document_words)
}

/// Words of `text` by the same segmentation, for source selections.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_text_word_count(text: TbStr) -> u32 {
    unsafe { text.get() }.map_or(0, |t| t.unicode_words().count() as u32)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_snapshot_page_count(s: *const TbSnapshot) -> u32 {
    unsafe { &*s }.pages.len() as u32
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_snapshot_page(s: *const TbSnapshot, i: u32) -> TbPage {
    unsafe { &*s }.pages.get(i as usize).copied().unwrap_or(TbPage { hash_hi: 0, hash_lo: 0, width_pt: 0.0, height_pt: 0.0 })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_snapshot_diagnostic_count(s: *const TbSnapshot) -> u32 {
    unsafe { &*s }.diags.len() as u32
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_snapshot_diagnostic(s: *const TbSnapshot, i: u32) -> TbDiagnostic {
    match unsafe { &*s }.diags.get(i as usize) {
        Some(d) => TbDiagnostic {
            severity: d.severity,
            origin: d.origin,
            path: TbStr::of(&d.path),
            utf16_start: d.start,
            utf16_end: d.end,
            message: TbStr::of(&d.message),
            hints: TbStr::of(&d.hints),
        },
        None => TbDiagnostic { severity: 0, origin: 0, path: NULL_STR, utf16_start: 0, utf16_end: 0, message: NULL_STR, hints: NULL_STR },
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_snapshot_render(
    s: *const TbSnapshot,
    page: u32,
    ppp: f32,
    width: *mut u32,
    height: *mut u32,
) -> TbBytes {
    let s = unsafe { &*s };
    let Some(p) = s.doc.as_ref().and_then(|d| d.pages().get(page as usize)) else { return NULL_BYTES };
    let pm = typst_render::render(
        p,
        &typst_render::RenderOptions { pixel_per_pt: typst::utils::Scalar::new(ppp as f64), render_bleed: false },
    );
    unsafe {
        *width = pm.width();
        *height = pm.height();
    }
    to_bytes(pm.data().to_vec())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_snapshot_pdf(s: *const TbSnapshot) -> TbBytes {
    let Some(d) = unsafe { &*s }.doc.as_ref() else { return NULL_BYTES };
    match typst_pdf::pdf(d, &typst_pdf::PdfOptions::default()) {
        Ok(v) => to_bytes(v),
        Err(_) => NULL_BYTES,
    }
}

/// PDF with `standard` 0 plain, 1 PDF/A-2b, 2 PDF/A-3b, 3 PDF/UA-1. On failure `*ok` is false and the bytes are the error text.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_snapshot_export_pdf(s: *const TbSnapshot, standard: u8, ok: *mut bool) -> TbBytes {
    use typst_pdf::{PdfOptions, PdfStandard, PdfStandards};
    let fail = |m: String| {
        unsafe { *ok = false };
        to_bytes(m.into_bytes())
    };
    let Some(d) = unsafe { &*s }.doc.as_ref() else { return fail("There is no compiled document.".into()) };
    let standards = match standard {
        1 => PdfStandards::new(&[PdfStandard::A_2b]),
        2 => PdfStandards::new(&[PdfStandard::A_3b]),
        3 => PdfStandards::new(&[PdfStandard::Ua_1]),
        _ => Ok(PdfStandards::default()),
    };
    let standards = match standards {
        Ok(v) => v,
        Err(e) => return fail(e.message().to_string()),
    };
    // PDF/A requires a creation date, which the document may not set itself.
    let timestamp = typst_kit::datetime::Time::system().today(None).map(typst_pdf::Timestamp::new_utc);
    match typst_pdf::pdf(d, &PdfOptions { standards, timestamp, ..PdfOptions::default() }) {
        Ok(v) => {
            unsafe { *ok = true };
            to_bytes(v)
        }
        Err(errs) => fail(
            errs.iter()
                .flat_map(|e| std::iter::once(e.message.to_string()).chain(e.hints.iter().map(|h| format!("hint: {}", h.v))))
                .collect::<Vec<_>>()
                .join("\n"),
        ),
    }
}

/// SVG (UTF-8) of one page; empty on a bad page.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_snapshot_svg(s: *const TbSnapshot, page: u32) -> TbBytes {
    let Some(p) = unsafe { &*s }.doc.as_ref().and_then(|d| d.pages().get(page as usize)) else { return NULL_BYTES };
    to_bytes(typst_svg::svg(p, &typst_svg::SvgOptions::default()).into_bytes())
}

/// JSON `[{"title","level","words","page"}]` of the words per heading section; "[]" without a document.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_snapshot_section_words(s: *const TbSnapshot) -> TbBytes {
    let v = unsafe { &*s }.doc.as_ref().map(section_words).unwrap_or_default();
    to_bytes(serde_json::to_vec(&v).unwrap_or_else(|_| b"[]".to_vec()))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_snapshot_free(s: *mut TbSnapshot) {
    if !s.is_null() {
        drop(unsafe { Box::from_raw(s) });
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_bytes_free(b: TbBytes) {
    if !b.ptr.is_null() {
        drop(unsafe { Box::from_raw(std::ptr::slice_from_raw_parts_mut(b.ptr, b.len)) });
    }
}

#[allow(dead_code)]
fn _assert_sync() {
    fn s<T: Sync>() {}
    s::<TbSnapshot>();
    s::<TbRuntime>();
}
#[allow(dead_code)]
fn _unused(_: FileError) {}

// ---- Syntax (highlighting and prose, no world) ----

pub struct TbSyntax {
    source: Source,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct TbRange16 {
    start: u32,
    end: u32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct TbSpan {
    start: u32,
    end: u32,
    tag: u8,
}

/// Exhaustive on purpose: a new upstream tag fails the build instead of silently getting a wrong number.
fn tag_u8(t: Tag) -> u8 {
    match t {
        Tag::Comment => 0,
        Tag::Punctuation => 1,
        Tag::Escape => 2,
        Tag::Strong => 3,
        Tag::Emph => 4,
        Tag::Link => 5,
        Tag::Raw => 6,
        Tag::Label => 7,
        Tag::Ref => 8,
        Tag::Heading => 9,
        Tag::ListMarker => 10,
        Tag::ListTerm => 11,
        Tag::MathDelimiter => 12,
        Tag::MathOperator => 13,
        Tag::MathGroupingParens => 14,
        Tag::Keyword => 15,
        Tag::Operator => 16,
        Tag::Number => 17,
        Tag::String => 18,
        Tag::Function => 19,
        Tag::Interpolated => 20,
        Tag::Error => 21,
    }
}

fn byte_window(lines: &Lines<String>, start: u32, end: u32) -> std::ops::Range<usize> {
    let end = (end as usize).min(lines.len_utf16());
    let a = lines.utf16_to_byte((start as usize).min(end)).unwrap_or(0);
    let b = lines.utf16_to_byte(end).unwrap_or(lines.len_bytes());
    a..b
}

/// Visits leaves overlapping `win`; `visit(leaf, tag)` gets the innermost tag of the leaf or its ancestors.
fn walk(node: &LinkedNode, inherited: Option<Tag>, win: &std::ops::Range<usize>, visit: &mut dyn FnMut(&LinkedNode, Option<Tag>)) {
    let r = node.range();
    if r.end <= win.start || r.start >= win.end {
        return;
    }
    let tag = highlight(node).or(inherited);
    let mut leaf = true;
    for c in node.children() {
        leaf = false;
        walk(&c, tag, win, visit);
    }
    if leaf {
        visit(node, tag);
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_syntax_new(text: TbStr) -> *mut TbSyntax {
    let Some(text) = (unsafe { text.get() }) else { return std::ptr::null_mut() };
    Box::into_raw(Box::new(TbSyntax { source: Source::detached(text) }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_syntax_free(s: *mut TbSyntax) {
    if !s.is_null() {
        drop(unsafe { Box::from_raw(s) });
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_syntax_set_text(s: *mut TbSyntax, text: TbStr) {
    if let Some(text) = unsafe { text.get() } {
        unsafe { &mut *s }.source.replace(text);
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_syntax_edit(
    s: *mut TbSyntax,
    start: u32,
    end: u32,
    replacement: TbStr,
    expected_len: u32,
    dirty: *mut TbRange16,
) -> bool {
    let src = &mut unsafe { &mut *s }.source;
    let Some(repl) = (unsafe { replacement.get() }) else { return false };
    let Some(range) = checked_edit(src.lines(), start, end, repl, expected_len) else { return false };
    let reparsed = src.edit(range, repl);
    let lines = src.lines();
    let to16 = |b: usize| lines.byte_to_utf16(b.min(lines.len_bytes())).unwrap_or(0) as u32;
    unsafe { *dirty = TbRange16 { start: to16(reparsed.start), end: to16(reparsed.end) } };
    true
}

/// Writes at most `cap` items, returns the total.
fn fill<T: Copy>(items: impl Iterator<Item = T>, out: *mut T, cap: usize) -> usize {
    let mut n = 0;
    for it in items {
        if n < cap {
            unsafe { out.add(n).write(it) };
        }
        n += 1;
    }
    n
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_syntax_highlight(s: *const TbSyntax, start: u32, end: u32, out: *mut TbSpan, cap: usize) -> usize {
    let src = &unsafe { &*s }.source;
    let lines = src.lines();
    let win = byte_window(lines, start, end);
    let mut spans = Vec::new();
    walk(&LinkedNode::new(src.root()), None, &win, &mut |leaf, tag| {
        let (Some(tag), r) = (tag, leaf.range()) else { return };
        if r.is_empty() {
            return;
        }
        let (a, b) = (lines.byte_to_utf16(r.start).unwrap_or(0) as u32, lines.byte_to_utf16(r.end).unwrap_or(0) as u32);
        spans.push(TbSpan { start: a, end: b, tag: tag_u8(tag) });
    });
    fill(spans.into_iter(), out, cap)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_syntax_prose(s: *const TbSyntax, start: u32, end: u32, out: *mut TbRange16, cap: usize) -> usize {
    let src = &unsafe { &*s }.source;
    let lines = src.lines();
    let win = byte_window(lines, start, end);
    let mut ranges: Vec<std::ops::Range<usize>> = Vec::new();
    walk(&LinkedNode::new(src.root()), None, &win, &mut |leaf, _| {
        // Text inside Raw is code. SmartQuote joins words ("don't") so the spell checker sees one range.
        let kind = leaf.kind();
        if !matches!(kind, SyntaxKind::Text | SyntaxKind::SmartQuote) || leaf.parent_kind() == Some(SyntaxKind::Raw) {
            return;
        }
        let r = leaf.range();
        match ranges.last_mut() {
            Some(last) if last.end == r.start => last.end = r.end,
            _ => ranges.push(r),
        }
    });
    let to16 = |b: usize| lines.byte_to_utf16(b).unwrap_or(0) as u32;
    fill(ranges.into_iter().map(|r| TbRange16 { start: to16(r.start), end: to16(r.end) }), out, cap)
}

/// The innermost strong (kind 0), emph (1) or `#underline[..]` call (2, with its `#`) that contains
/// [start, end] (a caret strictly inside, or a selection within it). False if there is none.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_syntax_enclosing(s: *const TbSyntax, kind: u8, start: u32, end: u32, out: *mut TbRange16) -> bool {
    let src = &unsafe { &*s }.source;
    let lines = src.lines();
    let (Some(a), Some(b)) = (lines.utf16_to_byte(start as usize), lines.utf16_to_byte(end as usize)) else { return false };
    let root = LinkedNode::new(src.root());
    let Some(leaf) = root.leaf_at(a, Side::After).or_else(|| root.leaf_at(a, Side::Before)) else { return false };
    let mut cur = Some(leaf);
    while let Some(n) = cur {
        let r = n.range();
        let inside = r.start <= a && b <= r.end && (a < b || (r.start < a && b < r.end));
        let found = if !inside { None } else {
            match (kind, n.kind()) {
                (0, SyntaxKind::Strong) | (1, SyntaxKind::Emph) => Some(r.clone()),
                (2, SyntaxKind::FuncCall) => {
                    let text = &src.text()[r.clone()];
                    (text.starts_with("underline[") && text.ends_with(']') && n.prev_sibling_kind() == Some(SyntaxKind::Hash))
                        .then(|| r.start - 1..r.end)
                }
                _ => None,
            }
        };
        if let Some(f) = found {
            let to16 = |b: usize| lines.byte_to_utf16(b).unwrap_or(0) as u32;
            unsafe { *out = TbRange16 { start: to16(f.start), end: to16(f.end) } };
            return true;
        }
        cur = n.parent().cloned();
    }
    false
}

/// Where Tab lands in one argument: a content block's inside, a named argument's value (a block value's
/// inside), else the expression. An unfinished `name:` gives an empty range after the colon.
fn arg_target(text: &str, n: &LinkedNode) -> std::ops::Range<usize> {
    let inside = |b: &LinkedNode| {
        let r = b.range();
        let closed = b.children().last().is_some_and(|c| c.kind() == SyntaxKind::RightBracket);
        r.start + 1..if closed { r.end - 1 } else { r.end }
    };
    match n.kind() {
        SyntaxKind::ContentBlock => inside(n),
        SyntaxKind::Error => n.range().start..n.range().start,
        SyntaxKind::Named => {
            let mut kids = n.children().filter(|c| !matches!(c.kind(), SyntaxKind::Space | SyntaxKind::LineComment | SyntaxKind::BlockComment));
            let colon = kids.by_ref().find(|c| c.kind() == SyntaxKind::Colon);
            match (colon, kids.next()) {
                (_, Some(v)) if v.kind() == SyntaxKind::ContentBlock => inside(&v),
                (_, Some(v)) if v.kind() != SyntaxKind::Error => v.range(),
                (Some(c), _) => {
                    let e = c.range().end;
                    let e = if text[e..].starts_with(' ') { e + 1 } else { e };
                    e..e
                }
                _ => n.range(),
            }
        }
        _ => n.range(),
    }
}

/// The innermost call arguments around `pos` with at least `min_targets` arguments whose delimited inside
/// holds `pos` (the callee name is not inside). `whole` gets the Args node, `out` one Tab target per
/// argument (see `arg_target`; a stray comma, as in an unfilled snippet `f(, x: )`, is an empty argument). Returns the number of targets, 0 if there is no such list.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_syntax_args(s: *const TbSyntax, pos: u32, min_targets: u32, whole: *mut TbRange16, out: *mut TbRange16, cap: usize) -> usize {
    let src = &unsafe { &*s }.source;
    let lines = src.lines();
    let Some(byte) = lines.utf16_to_byte(pos as usize) else { return 0 };
    let root = LinkedNode::new(src.root());
    let Some(leaf) = root.leaf_at(byte, Side::After).or_else(|| root.leaf_at(byte, Side::Before)) else { return 0 };
    let mut cur = Some(leaf);
    while let Some(n) = cur {
        cur = n.parent().cloned();
        if n.kind() != SyntaxKind::Args {
            continue;
        }
        let kids: Vec<LinkedNode> = n.children().collect();
        let open = kids.iter().find(|c| c.kind() == SyntaxKind::LeftParen).map(|c| c.range().end);
        let close = kids.iter().find(|c| c.kind() == SyntaxKind::RightParen).map(|c| c.range().start);
        let in_paren = open.is_some_and(|o| o <= byte && byte <= close.unwrap_or(n.range().end));
        let in_block = kids.iter().any(|c| c.kind() == SyntaxKind::ContentBlock && c.range().start < byte && byte < c.range().end);
        let args: Vec<&LinkedNode> = kids.iter().filter(|c| !matches!(c.kind(),
            SyntaxKind::LeftParen | SyntaxKind::RightParen | SyntaxKind::Comma | SyntaxKind::Space | SyntaxKind::LineComment
            | SyntaxKind::BlockComment)).filter(|c| c.kind() != SyntaxKind::Error || &src.text()[c.range()] == ",").collect();
        if !(in_paren || in_block) || args.len() < (min_targets as usize).max(1) {
            continue;
        }
        let to16 = |b: usize| lines.byte_to_utf16(b).unwrap_or(0) as u32;
        let r = n.range();
        unsafe { *whole = TbRange16 { start: to16(r.start), end: to16(r.end) } };
        let text = src.text();
        return fill(args.iter().map(|a| { let t = arg_target(text, a); TbRange16 { start: to16(t.start), end: to16(t.end) } }), out, cap);
    }
    0
}

/// True if the rightmost path of `n` has an Error child: the expression is still being written.
fn unfinished(n: &LinkedNode) -> bool {
    n.children().any(|c| c.kind() == SyntaxKind::Error) || n.children().last().is_some_and(|c| unfinished(&c))
}

/// What the caret is editing: 0 markup, 1 code, 2 math, 3 text that is not syntax (string, raw, comment).
/// Decided by the leaf before `pos` and its parent: embedded code (`#f(..)`) is any parent other than
/// the markup and math nodes listed below, Equation and a content block's own bracket.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_syntax_mode(s: *const TbSyntax, pos: u32) -> u8 {
    let src = &unsafe { &*s }.source;
    let Some(byte) = src.lines().utf16_to_byte(pos as usize) else { return 0 };
    let Some(leaf) = LinkedNode::new(src.root()).leaf_at(byte, Side::Before) else { return 0 };
    let inside = |r: std::ops::Range<usize>| r.start < byte && byte < r.end;
    let parent = leaf.parent();
    match leaf.kind() {
        SyntaxKind::LineComment if byte > leaf.range().start => return 3,
        SyntaxKind::BlockComment | SyntaxKind::Str if inside(leaf.range()) => return 3,
        _ => {}
    }
    if parent.is_some_and(|p| p.kind() == SyntaxKind::Raw && inside(p.range())) {
        return 3;
    }
    // The space after an unfinished `#include ` belongs to the markup, but the caret still writes code.
    if leaf.kind() == SyntaxKind::Space && leaf.parent_kind() == Some(SyntaxKind::Markup) && !src.text()[leaf.range()].contains('\n') {
        // shortcut: any Error on the rightmost path counts, so a call with an error in its middle also reads as code.
        let prev = leaf.prev_sibling();
        if prev.as_ref().is_some_and(unfinished) && prev.and_then(|p| p.prev_sibling_kind()) == Some(SyntaxKind::Hash) {
            return 1;
        }
    }
    match leaf.parent_kind() {
        // Markup nodes whose children are markup; embedded code under them has its own call or block parent.
        None | Some(SyntaxKind::Markup | SyntaxKind::Strong | SyntaxKind::Emph | SyntaxKind::Heading | SyntaxKind::ListItem
            | SyntaxKind::EnumItem | SyntaxKind::TermItem) => 0,
        Some(SyntaxKind::Math | SyntaxKind::MathDelimited | SyntaxKind::MathAttach | SyntaxKind::MathFrac | SyntaxKind::MathRoot) => 2,
        Some(SyntaxKind::Equation) => match leaf.kind() {
            SyntaxKind::Dollar if leaf.index() == 0 => 2,
            SyntaxKind::Dollar => 0,
            _ => 2,
        },
        Some(SyntaxKind::ContentBlock) if leaf.kind() == SyntaxKind::LeftBracket => 0,
        Some(_) => 1,
    }
}

// ---- Completion ----

struct OwnedCompletion {
    kind: u8,
    label: String,
    apply: String,
    detail: String,
    symbol: String,
}

pub struct TbCompletions {
    from: u32,
    items: Vec<OwnedCompletion>,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct TbCompletion {
    kind: u8,
    label: TbStr,
    apply: TbStr,
    detail: TbStr,
    symbol: TbStr,
}

/// Exhaustive on purpose, like tag_u8.
fn kind_u8(k: &CompletionKind) -> u8 {
    match k {
        CompletionKind::Syntax => 0,
        CompletionKind::Func => 1,
        CompletionKind::Type => 2,
        CompletionKind::Param => 3,
        CompletionKind::Constant => 4,
        CompletionKind::Path => 5,
        CompletionKind::Package => 6,
        CompletionKind::Label => 7,
        CompletionKind::Font => 8,
        CompletionKind::Symbol(_) => 9,
    }
}

/// Refreshes the package list (the only mutation), then completes `text_override` (or the overlay) of `path`.
unsafe fn complete_impl(w: *mut TbWorld, path: TbStr, text: Option<TbStr>, cursor16: u32, explicit: bool) -> *mut TbCompletions {
    let w = unsafe { &mut *w };
    w.refresh_data_dir();
    let index = w.shared_packages.read().unwrap_or_else(|e| e.into_inner()).clone();
    // shortcut: the local folder is rescanned per request (a few readdirs), so new packages show up at once;
    // upgrade to a cached scan if a data dir ever holds thousands of packages.
    w.packages = match w.data_dir.as_deref() {
        Some(d) => index.iter().cloned().chain(scan_local(d)).collect(),
        None => index,
    };
    let w = &*w;
    let Some(id) = unsafe { path.get() }.and_then(project_id) else { return std::ptr::null_mut() };
    // A temporary Source with the overlay's FileId; overlays and world state stay untouched.
    let tmp;
    let src = match text {
        Some(t) => {
            let Some(t) = (unsafe { t.get() }) else { return std::ptr::null_mut() };
            tmp = Source::new(id, t.to_string());
            &tmp
        }
        None => match w.overlays.get(&id) {
            Some(s) => s,
            None => return std::ptr::null_mut(),
        },
    };
    let lines = src.lines();
    let u = cursor16 as usize;
    let Some(cursor) = lines.utf16_to_byte(u).filter(|&b| lines.byte_to_utf16(b) == Some(u)) else {
        return std::ptr::null_mut();
    };
    let result = stacker::grow(32 << 20, || typst_ide::autocomplete(w, w.last_doc.as_ref(), src, cursor, explicit));
    let (from, items) = result.unwrap_or((cursor, Vec::new()));
    let from = lines.byte_to_utf16(from.min(cursor)).unwrap_or(0) as u32;
    let items = items
        .into_iter()
        .map(|c| OwnedCompletion {
            kind: kind_u8(&c.kind),
            symbol: match &c.kind {
                CompletionKind::Symbol(g) => g.to_string(),
                _ => String::new(),
            },
            label: c.label.to_string(),
            apply: c.apply.map(|a| a.to_string()).unwrap_or_default(),
            detail: c.detail.map(|d| d.to_string()).unwrap_or_default(),
        })
        .collect();
    Box::into_raw(Box::new(TbCompletions { from, items }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_world_complete(w: *mut TbWorld, path: TbStr, cursor16: u32, explicit: bool) -> *mut TbCompletions {
    unsafe { complete_impl(w, path, None, cursor16, explicit) }
}

/// Like `tb_world_complete`, but for `text` as the content of `path` (any file id, overlay or not). Nothing is stored.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_world_complete_text(w: *mut TbWorld, path: TbStr, text: TbStr, cursor16: u32, explicit: bool) -> *mut TbCompletions {
    unsafe { complete_impl(w, path, Some(text), cursor16, explicit) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_completions_from(c: *const TbCompletions) -> u32 {
    unsafe { &*c }.from
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_completions_count(c: *const TbCompletions) -> u32 {
    unsafe { &*c }.items.len() as u32
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_completions_get(c: *const TbCompletions, i: u32) -> TbCompletion {
    match unsafe { &*c }.items.get(i as usize) {
        Some(o) => TbCompletion {
            kind: o.kind,
            label: TbStr::of(&o.label),
            apply: TbStr::of(&o.apply),
            detail: TbStr::of(&o.detail),
            symbol: TbStr::of(&o.symbol),
        },
        None => TbCompletion { kind: 0, label: NULL_STR, apply: NULL_STR, detail: NULL_STR, symbol: NULL_STR },
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_completions_free(c: *mut TbCompletions) {
    if !c.is_null() {
        drop(unsafe { Box::from_raw(c) });
    }
}


// ---- Jump (preview <-> source) ----

#[repr(C)]
#[derive(Clone, Copy)]
pub struct TbPosition {
    page: u32,
    x_pt: f32,
    y_pt: f32,
}

const JUMP_NONE: u8 = 0;
const JUMP_FILE: u8 = 1;
const JUMP_URL: u8 = 2;
const JUMP_POSITION: u8 = 3;

pub struct TbJump {
    kind: u8,
    path: String,
    offset16: u32,
    url: String,
    position: TbPosition,
}

const NO_POSITION: TbPosition = TbPosition { page: 0, x_pt: 0.0, y_pt: 0.0 };

fn to_position(p: &PagedPosition) -> TbPosition {
    TbPosition { page: (p.page.get() - 1) as u32, x_pt: p.point.x.to_pt() as f32, y_pt: p.point.y.to_pt() as f32 }
}

fn resolve_jump(w: &TbWorld, j: Jump) -> TbJump {
    let none = resolve_none();
    match j {
        Jump::File(id, byte) => {
            let Ok(src) = w.source(id) else { return none };
            let Some(offset16) = src.lines().byte_to_utf16(byte) else { return none };
            // Package files have no project-relative path; Swift treats the empty path as a miss.
            let path = if matches!(id.root(), VirtualRoot::Project) { id.vpath().get_without_slash().to_string() } else { String::new() };
            TbJump { kind: JUMP_FILE, path, offset16: offset16 as u32, ..none }
        }
        Jump::Url(u) => TbJump { kind: JUMP_URL, url: u.as_str().to_string(), ..none },
        Jump::Position(p) => TbJump { kind: JUMP_POSITION, position: to_position(&p), ..none },
    }
}

/// Resolves against `shown`, the document the preview displays, not `last_doc`. NULL if it has no document.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_world_jump_from_click(w: *mut TbWorld, shown: *const TbSnapshot, click: TbPosition) -> *mut TbJump {
    let (w, shown) = (unsafe { &*w }, unsafe { &*shown });
    let Some(doc) = shown.doc.as_ref() else { return std::ptr::null_mut() };
    let (Some(page), true) = (std::num::NonZeroUsize::new(click.page as usize + 1), click.x_pt.is_finite() && click.y_pt.is_finite()) else {
        return Box::into_raw(Box::new(resolve_none()));
    };
    let pos = PagedPosition { page, point: Point::new(Abs::pt(click.x_pt as f64), Abs::pt(click.y_pt as f64)) };
    let jump = typst_ide::jump_from_click(w, doc, &pos);
    Box::into_raw(Box::new(jump.map(|j| resolve_jump(w, j)).unwrap_or_else(resolve_none)))
}

fn resolve_none() -> TbJump {
    TbJump { kind: JUMP_NONE, path: String::new(), offset16: 0, url: String::new(), position: NO_POSITION }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_jump_kind(j: *const TbJump) -> u8 {
    unsafe { &*j }.kind
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_jump_path(j: *const TbJump) -> TbStr {
    TbStr::of(&unsafe { &*j }.path)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_jump_offset16(j: *const TbJump) -> u32 {
    unsafe { &*j }.offset16
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_jump_url(j: *const TbJump) -> TbStr {
    TbStr::of(&unsafe { &*j }.url)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_jump_position(j: *const TbJump) -> TbPosition {
    unsafe { &*j }.position
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_jump_free(j: *mut TbJump) {
    if !j.is_null() {
        drop(unsafe { Box::from_raw(j) });
    }
}

/// Positions in the last successful document for the leaf at `cursor16`. Writes at most `cap`, returns the total.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_world_jump_from_cursor(w: *mut TbWorld, path: TbStr, cursor16: u32, out: *mut TbPosition, cap: usize) -> usize {
    let w = unsafe { &*w };
    let (Some(doc), Some(src)) = (w.last_doc.as_ref(), unsafe { path.get() }.and_then(project_id).and_then(|id| w.overlays.get(&id))) else {
        return 0;
    };
    let lines = src.lines();
    let u = cursor16 as usize;
    let Some(cursor) = lines.utf16_to_byte(u).filter(|&b| lines.byte_to_utf16(b) == Some(u)) else { return 0 };
    let positions = typst_ide::jump_from_cursor(doc, src, cursor);
    fill(positions.iter().map(to_position), out, cap)
}

// ---- Equation preview (hover) ----

struct EqCluster {
    page: usize,
    min: Point,
    max: Point,
    /// The equation's own items with the transform from their parent frame to the page.
    items: Vec<(typst::layout::Transform, Point, FrameItem)>,
}

struct EqWalk {
    eq: typst::syntax::Span,
    page: usize,
    open: Vec<typst::introspection::Location>,
    cur: Option<usize>,
    clusters: Vec<EqCluster>,
}

impl EqWalk {
    fn add(&mut self, ts: typst::layout::Transform, corners: [Point; 4], at: Point, item: &FrameItem) {
        if self.open.is_empty() {
            return;
        }
        let idx = match self.cur {
            Some(i) if self.clusters[i].page == self.page => i,
            _ => {
                self.clusters.push(EqCluster { page: self.page, min: Point::splat(Abs::inf()), max: Point::splat(-Abs::inf()), items: Vec::new() });
                self.cur = Some(self.clusters.len() - 1);
                self.clusters.len() - 1
            }
        };
        let c = &mut self.clusters[idx];
        c.items.push((ts, at, item.clone()));
        for p in corners {
            let p = p.transform(ts);
            c.min = c.min.min(p);
            c.max = c.max.max(p);
        }
    }

    /// Everything between the Start and End tag of an equation node's element belongs to it, macros included.
    fn walk(&mut self, frame: &Frame, ts: typst::layout::Transform) {
        use typst::introspection::Tag;
        for (pos, item) in frame.items() {
            let at = |x0: Abs, y0: Abs, x1: Abs, y1: Abs| {
                [Point::new(pos.x + x0, pos.y + y0), Point::new(pos.x + x1, pos.y + y0), Point::new(pos.x + x1, pos.y + y1), Point::new(pos.x + x0, pos.y + y1)]
            };
            match item {
                FrameItem::Group(g) => {
                    let inner = ts.pre_concat(typst::layout::Transform::translate(pos.x, pos.y)).pre_concat(g.transform);
                    self.walk(&g.frame, inner);
                }
                FrameItem::Text(t) => {
                    let m = t.font.metrics();
                    let (top, bottom) = (-m.ascender.at(t.size), -m.descender.at(t.size));
                    let (mut x, mut lo, mut hi) = (Abs::zero(), top, bottom);
                    let mut x1 = Abs::zero();
                    for g in &t.glyphs {
                        let dy = -g.y_offset.at(t.size);
                        lo = lo.min(top + dy);
                        hi = hi.max(bottom + dy);
                        x += g.x_advance.at(t.size);
                        x1 = x1.max(x);
                    }
                    self.add(ts, at(Abs::zero(), lo, x1, hi), *pos, item);
                }
                FrameItem::Shape(sh, _) => {
                    let r = sh.bbox(true);
                    self.add(ts, at(r.min.x, r.min.y, r.max.x, r.max.y), *pos, item);
                }
                FrameItem::Image(_, size, _) => self.add(ts, at(Abs::zero(), Abs::zero(), size.x, size.y), *pos, item),
                FrameItem::Tag(Tag::Start(c, _)) if c.span() == self.eq => {
                    if let Some(l) = c.location() {
                        self.open.push(l);
                        self.cur = None;
                    }
                }
                FrameItem::Tag(Tag::End(l, _, _)) if self.open.last() == Some(l) => {
                    self.open.pop();
                    self.cur = None;
                }
                _ => {}
            }
        }
    }
}

/// The compiled look of the equation around `cursor16`, cropped from the last successful document and
/// rendered at `ppp` (RGBA, opaque). Empty if the file changed since that compile, the cursor is not in math,
/// or the equation is not in the document. Several occurrences: the one nearest the cursor's jump point.
/// Writes the equation's UTF-16 range and the image's size in points.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_world_equation_image(
    w: *mut TbWorld,
    path: TbStr,
    cursor16: u32,
    ppp: f32,
    width: *mut u32,
    height: *mut u32,
    width_pt: *mut f32,
    height_pt: *mut f32,
    range: *mut TbRange16,
) -> TbBytes {
    let w = unsafe { &*w };
    let (Some(doc), Some(id)) = (w.last_doc.as_ref(), unsafe { path.get() }.and_then(project_id)) else { return NULL_BYTES };
    let Some(src) = w.overlays.get(&id) else { return NULL_BYTES };
    if w.compiled_text.get(&id) != Some(&typst::utils::hash128(src.text())) || !ppp.is_finite() || ppp <= 0.0 {
        return NULL_BYTES;
    }
    let lines = src.lines();
    let u = cursor16 as usize;
    let Some(cursor) = lines.utf16_to_byte(u).filter(|&b| lines.byte_to_utf16(b) == Some(u)) else { return NULL_BYTES };
    let root = LinkedNode::new(src.root());
    let Some(leaf) = root.leaf_at(cursor, Side::After).or_else(|| root.leaf_at(cursor, Side::Before)) else { return NULL_BYTES };
    let mut cur = Some(leaf);
    while let Some(n) = cur.as_ref().filter(|n| n.kind() != SyntaxKind::Equation) {
        cur = n.parent().cloned();
    }
    let Some(eq) = cur else { return NULL_BYTES };
    let mut walk = EqWalk { eq: eq.span(), page: 0, open: Vec::new(), cur: None, clusters: Vec::new() };
    for (i, p) in doc.pages().iter().enumerate() {
        walk.page = i;
        walk.cur = None;
        walk.open.clear();
        walk.walk(&p.frame, typst::layout::Transform::identity());
    }
    let jump = typst_ide::jump_from_cursor(doc, src, cursor);
    let dist = |c: &EqCluster| {
        let Some(j) = jump.first() else { return 0.0 };
        if j.page.get() - 1 != c.page {
            return f64::MAX;
        }
        let (x, y) = (j.point.x.to_pt(), j.point.y.to_pt());
        let dx = (c.min.x.to_pt() - x).max(x - c.max.x.to_pt()).max(0.0);
        let dy = (c.min.y.to_pt() - y).max(y - c.max.y.to_pt()).max(0.0);
        dx.hypot(dy)
    };
    let Some(best) = walk.clusters.iter().filter(|c| c.min.x <= c.max.x).min_by(|a, b| dist(a).total_cmp(&dist(b))) else { return NULL_BYTES };
    let pad = Abs::pt(3.0);
    let (origin, size) = (Point::new(best.min.x - pad, best.min.y - pad), Point::new(best.max.x - best.min.x + pad * 2.0, best.max.y - best.min.y + pad * 2.0));
    let page = &doc.pages()[best.page];
    // Only the equation's own items: neighbouring page content inside the padding must not show.
    let mut frame = Frame::hard(size.to_size());
    for (ts, pos, item) in &best.items {
        let mut inner = Frame::soft(typst::layout::Size::zero());
        inner.push(*pos, item.clone());
        let mut g = typst::layout::GroupItem::new(inner);
        g.transform = *ts;
        frame.push(Point::new(-origin.x, -origin.y), FrameItem::Group(g));
    }
    let mut cropped = page.clone();
    cropped.frame = frame;
    cropped.bleed = Default::default();
    // Black math stays readable on the dark popup: transparent and gradient fills become white.
    let fill = match page.fill_or_white() {
        Some(p @ typst::visualize::Paint::Solid(_)) => p,
        _ => typst::visualize::Color::WHITE.into(),
    };
    cropped.fill = typst::foundations::Smart::Custom(Some(fill));
    let ppp = ppp.min(1600.0 / size.x.to_pt().max(1.0) as f32);
    let pm = stacker::grow(32 << 20, || {
        typst_render::render(&cropped, &typst_render::RenderOptions { pixel_per_pt: typst::utils::Scalar::new(ppp as f64), render_bleed: false })
    });
    let to16 = |b: usize| lines.byte_to_utf16(b).unwrap_or(0) as u32;
    unsafe {
        *width = pm.width();
        *height = pm.height();
        *width_pt = size.x.to_pt() as f32;
        *height_pt = size.y.to_pt() as f32;
        *range = TbRange16 { start: to16(eq.range().start), end: to16(eq.range().end) };
    }
    to_bytes(pm.data().to_vec())
}

// ---- Hover (typst-ide tooltip) ----

pub struct TbHover {
    kind: u8,
    text: String,
    range: TbRange16,
}

/// Tooltip at `cursor16` (Side::After) using `last_doc` for labels. NULL if there is nothing to show.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_world_hover(w: *mut TbWorld, path: TbStr, cursor16: u32) -> *mut TbHover {
    let w = unsafe { &*w };
    let Some(src) = unsafe { path.get() }.and_then(project_id).and_then(|id| w.overlays.get(&id)) else {
        return std::ptr::null_mut();
    };
    let lines = src.lines();
    let u = cursor16 as usize;
    let Some(cursor) = lines.utf16_to_byte(u).filter(|&b| lines.byte_to_utf16(b) == Some(u)) else {
        return std::ptr::null_mut();
    };
    let Some(leaf) = LinkedNode::new(src.root()).leaf_at(cursor, Side::After) else { return std::ptr::null_mut() };
    let range = leaf.range();
    let tip = stacker::grow(32 << 20, || typst_ide::tooltip(w, w.last_doc.as_ref(), src, cursor, Side::After));
    let (kind, text) = match tip {
        Some(typst_ide::Tooltip::Text(t)) => (1, t),
        Some(typst_ide::Tooltip::Code(t)) => (2, t),
        None => return std::ptr::null_mut(),
    };
    let to16 = |b: usize| lines.byte_to_utf16(b).unwrap_or(0) as u32;
    let range = TbRange16 { start: to16(range.start), end: to16(range.end) };
    Box::into_raw(Box::new(TbHover { kind, text: text.to_string(), range }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_hover_kind(h: *const TbHover) -> u8 {
    unsafe { &*h }.kind
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_hover_text(h: *const TbHover) -> TbStr {
    TbStr::of(&unsafe { &*h }.text)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_hover_range(h: *const TbHover) -> TbRange16 {
    unsafe { &*h }.range
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_hover_free(h: *mut TbHover) {
    if !h.is_null() {
        drop(unsafe { Box::from_raw(h) });
    }
}

// ---- Definition (typst-ide) ----

pub struct TbDefinition {
    kind: u8,
    path: String,
    range: TbRange16,
    name: String,
    docs: String,
    url: String,
    /// The function under the cursor written out with every parameter and its types (Quick Help); empty otherwise.
    signature: String,
}

/// Definition of the item at `cursor16` in overlay `path`, resolved through imports and packages, using `last_doc`
/// for labels. Tries Side::After, then Side::Before. Kinds: 0 span in the project, 1 file in the project, 2 std
/// (`name` is the item's name), 3 package (`name` is the package spec, `path` the file in it). NULL if none.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_world_definition(w: *mut TbWorld, path: TbStr, cursor16: u32) -> *mut TbDefinition {
    let w = unsafe { &*w };
    let Some(src) = unsafe { path.get() }.and_then(project_id).and_then(|id| w.overlays.get(&id)) else {
        return std::ptr::null_mut();
    };
    let lines = src.lines();
    let u = cursor16 as usize;
    let Some(cursor) = lines.utf16_to_byte(u).filter(|&b| lines.byte_to_utf16(b) == Some(u)) else {
        return std::ptr::null_mut();
    };
    let found = stacker::grow(32 << 20, || {
        [Side::After, Side::Before].into_iter().find_map(|side| typst_ide::definition(w, w.last_doc.as_ref(), src, cursor, side))
    });
    let none = TbRange16 { start: 0, end: 0 };
    let mut field_name = None;
    let found = found.or_else(|| {
        let (name, v) = std_field_at(w, src, cursor)?;
        field_name = Some(name);
        Some(typst_ide::Definition::Std(v))
    });
    let std_value = match &found { Some(typst_ide::Definition::Std(v)) => Some(v.clone()), _ => None };
    let mut def = match found {
        None => return std::ptr::null_mut(),
        Some(typst_ide::Definition::Std(v)) => {
            let name = field_name.or_else(|| match &v {
                Value::Func(f) => f.name().map(|n| n.to_string()),
                Value::Type(t) => Some(t.short_name().to_string()),
                Value::Module(m) => Some(m.name().map_or_else(String::new, |n| n.to_string())),
                _ => None,
            });
            let docs = v.docs().unwrap_or_default().to_string();
            let url = std_docs_url(w.library(), &v).unwrap_or_default();
            TbDefinition { kind: 2, path: String::new(), range: none, name: name.unwrap_or_else(|| format!("{}", v.ty().short_name())), docs, url, signature: String::new() }
        }
        Some(typst_ide::Definition::File(id)) => locate(id, false, none),
        Some(typst_ide::Definition::Span(span)) => {
            let (Some(id), Some(range)) = (span.id(), w.range(span)) else { return std::ptr::null_mut() };
            let Ok(file) = w.source(id) else { return std::ptr::null_mut() };
            let l = file.lines();
            let to16 = |b: usize| l.byte_to_utf16(b).unwrap_or(0) as u32;
            locate(id, true, TbRange16 { start: to16(range.start), end: to16(range.end) })
        }
    };
    def.signature = stacker::grow(32 << 20, || signature_at(w, src, cursor, std_value.as_ref())).unwrap_or_default();
    Box::into_raw(Box::new(def))
}

/// The function named at `cursor` (or `known`, the standard-library value already found) written out like
/// `figure(\n  body: content,\n  alt: none | str,\n)`: every parameter with the types it accepts.
fn signature_at(w: &TbWorld, src: &Source, cursor: usize, known: Option<&Value>) -> Option<String> {
    let func = match known {
        Some(Value::Func(f)) => Some(f.clone()),
        _ => {
            let root = LinkedNode::new(src.root());
            [Side::After, Side::Before].into_iter().find_map(|side| {
                let leaf = root.leaf_at(cursor, side)?;
                if !matches!(leaf.kind(), SyntaxKind::Ident | SyntaxKind::MathIdent) { return None }
                // `calc.max`: the field's value is that of the whole access.
                let node = match leaf.parent() {
                    Some(p) if p.cast::<ast::FieldAccess>().is_some_and(|a| a.field().span() == leaf.span()) => p.clone(),
                    _ => leaf.clone(),
                };
                typst_ide::analyze_expr(w, &node).into_iter().find_map(|(v, _)| match v { Value::Func(f) => Some(f), _ => None })
            })
        }
    }?;
    let name = func.name().unwrap_or("function").to_string();
    let params: Vec<String> = func.params().map(|p| param_label(&p)).collect();
    if params.is_empty() { return Some(format!("{name}()")) }
    Some(format!("{name}(\n{}\n)", params.iter().map(|p| format!("  {p}")).collect::<Vec<_>>().join(",\n")))
}

/// One parameter as Quick Help and signature help show it: `..children: content`, `loud: false`, `name`.
fn param_label(p: &typst::foundations::ParamInfo) -> String {
    use typst::foundations::{ClosureParamInfo, ParamInfo};
    match p {
        ParamInfo::Native(n) => format!("{}{}: {}", if n.variadic { ".." } else { "" }, n.name, cast_types(&n.input)),
        ParamInfo::Closure(c) => match &c.v {
            ClosureParamInfo::Pos { name } => name.as_ref().map_or_else(|| "_".to_string(), |n| n.to_string()),
            ClosureParamInfo::Sink { name } => format!("..{}", name.as_ref().map_or_else(String::new, |n| n.to_string())),
            ClosureParamInfo::Named { name, default } => format!("{name}: {}", typst::foundations::Repr::repr(default)),
        },
        ParamInfo::Plugin => "..args: bytes".to_string(),
    }
}

/// The types a parameter accepts, `none | str | function`: `none` and `auto` first, the rest in declaration order, no repeats.
fn cast_types(info: &typst::foundations::CastInfo) -> String {
    use typst::foundations::CastInfo;
    let mut out: Vec<String> = Vec::new();
    info.walk(|c| {
        let s = match c {
            CastInfo::Any => "any".to_string(),
            CastInfo::Value(v, _) => typst::foundations::Repr::repr(v).to_string(),
            CastInfo::Type(t) => t.short_name().to_string(),
            CastInfo::Union(_) => return,
        };
        if !out.contains(&s) { out.push(s) }
    });
    // `none` and `auto` lead, as in Typst's documentation.
    out.sort_by_key(|t| match t.as_str() { "none" => 0, "auto" => 1, _ => 2 });
    if out.is_empty() { "any".to_string() } else { out.join(" | ") }
}

/// `typst_ide::definition` does not follow `calc.max`; resolve a field of a global module (`calc`, `math`, `pdf`, ..) by hand.
fn std_field_at(w: &TbWorld, src: &Source, cursor: usize) -> Option<(String, Value)> {
    let root = LinkedNode::new(src.root());
    [Side::After, Side::Before].into_iter().find_map(|side| {
        let leaf = root.leaf_at(cursor, side)?;
        let access = leaf.parent()?.cast::<ast::FieldAccess>()?;
        let field = access.field();
        if field.span() != leaf.span() {
            return None;
        }
        let ast::Expr::Ident(target) = access.target() else { return None };
        let lib = w.library();
        let b = lib.global.scope().get(target.get())?;
        let Value::Module(m) = b.read() else { return None };
        let item = m.scope().get(field.get())?;
        Some((field.get().to_string(), item.read().clone()))
    })
}

/// Whether the binding's value is the function or type `v`.
fn same_item(b: &typst::foundations::Binding, v: &Value) -> bool {
    match (b.read(), v) {
        (Value::Func(a), Value::Func(c)) => a == c,
        (Value::Type(a), Value::Type(c)) => a == c,
        _ => false,
    }
}

/// The typst.app documentation page of a standard-library function or type, found by searching the global scope,
/// the math scope and one level of modules. None when unsure (e.g. constants, `.with(..)` functions).
fn std_docs_url(lib: &Library, v: &Value) -> Option<String> {
    const BASE: &str = "https://typst.app/docs/reference";
    if let Value::Module(m) = v {
        let name = m.name()?;
        return Some(format!("{BASE}/{}/{name}/", lib.global.scope().get(name)?.category()?.name()));
    }
    if !matches!(v, Value::Func(_) | Value::Type(_)) {
        return None;
    }
    for (name, b) in lib.global.scope().iter() {
        if same_item(b, v) {
            return Some(format!("{BASE}/{}/{name}/", b.category()?.name()));
        }
    }
    for (name, b) in lib.math.scope().iter() {
        if same_item(b, v) {
            return Some(format!("{BASE}/{}/{name}/", b.category().map_or("math", |c| c.name())));
        }
    }
    for (mname, mb) in lib.global.scope().iter() {
        let Value::Module(m) = mb.read() else { continue };
        let cat = mb.category()?.name();
        for (name, b) in m.scope().iter() {
            if same_item(b, v) {
                // Modules named like their category (`pdf`, `html`) have a page per item; others (`calc`) one page with anchors.
                return Some(if mname.as_str() == cat { format!("{BASE}/{cat}/{name}/") } else { format!("{BASE}/{cat}/{mname}/#functions-{name}") });
            }
        }
    }
    None
}

fn locate(id: FileId, span: bool, range: TbRange16) -> TbDefinition {
    let path = id.vpath().get_without_slash().to_string();
    match id.root() {
        VirtualRoot::Project => TbDefinition { kind: if span { 0 } else { 1 }, path, range, name: String::new(), docs: String::new(), url: String::new(), signature: String::new() },
        VirtualRoot::Package(spec) => TbDefinition { kind: 3, path, range, name: spec.to_string(), docs: String::new(), url: String::new(), signature: String::new() },
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_definition_kind(d: *const TbDefinition) -> u8 {
    unsafe { &*d }.kind
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_definition_path(d: *const TbDefinition) -> TbStr {
    TbStr::of(&unsafe { &*d }.path)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_definition_range16(d: *const TbDefinition) -> TbRange16 {
    unsafe { &*d }.range
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_definition_name(d: *const TbDefinition) -> TbStr {
    TbStr::of(&unsafe { &*d }.name)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_definition_docs(d: *const TbDefinition) -> TbStr {
    TbStr::of(&unsafe { &*d }.docs)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_definition_url(d: *const TbDefinition) -> TbStr {
    TbStr::of(&unsafe { &*d }.url)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_definition_signature(d: *const TbDefinition) -> TbStr {
    TbStr::of(&unsafe { &*d }.signature)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_definition_free(d: *mut TbDefinition) {
    if !d.is_null() {
        drop(unsafe { Box::from_raw(d) });
    }
}

// ---- Bindings (definitions and uses of one file) ----

#[derive(Serialize)]
struct BDef {
    name: String,
    range: [u32; 2],
    kind: &'static str,
    scope: [u32; 2],
    top: bool,
    #[serde(skip_serializing_if = "std::ops::Not::not")]
    implicit: bool,
}

#[derive(Serialize)]
struct BUse {
    name: String,
    range: [u32; 2],
}

#[derive(Serialize)]
struct BField {
    module: String,
    name: String,
    range: [u32; 2],
}

#[derive(Serialize)]
struct BItem {
    name: String,
    #[serde(rename = "nameRange")]
    name_range: [u32; 2],
    #[serde(skip_serializing_if = "Option::is_none")]
    alias: Option<String>,
    #[serde(rename = "aliasRange", skip_serializing_if = "Option::is_none")]
    alias_range: Option<[u32; 2]>,
}

#[derive(Serialize)]
struct BAlias {
    name: String,
    range: [u32; 2],
}

#[derive(Serialize)]
struct BImport {
    path: String,
    #[serde(rename = "pathRange")]
    path_range: [u32; 2],
    items: Vec<BItem>,
    wildcard: bool,
    scope: [u32; 2],
    #[serde(rename = "moduleAlias", skip_serializing_if = "Option::is_none")]
    module_alias: Option<BAlias>,
}

#[derive(Serialize, Default)]
struct Bindings {
    defs: Vec<BDef>,
    uses: Vec<BUse>,
    fields: Vec<BField>,
    imports: Vec<BImport>,
}

struct Binder<'a> {
    src: &'a Source,
    out: Bindings,
}

fn is_trivia(k: SyntaxKind) -> bool {
    matches!(k, SyntaxKind::Space | SyntaxKind::LineComment | SyntaxKind::BlockComment)
}

fn is_ident(k: SyntaxKind) -> bool {
    matches!(k, SyntaxKind::Ident | SyntaxKind::MathIdent)
}

fn significant<'a>(n: &LinkedNode<'a>) -> Vec<LinkedNode<'a>> {
    n.children().filter(|c| !is_trivia(c.kind())).collect()
}

impl Binder<'_> {
    fn r16(&self, r: std::ops::Range<usize>) -> [u32; 2] {
        let l = self.src.lines();
        [l.byte_to_utf16(r.start).unwrap_or(0) as u32, l.byte_to_utf16(r.end).unwrap_or(0) as u32]
    }

    fn text(&self, n: &LinkedNode) -> String {
        self.src.text()[n.range()].to_string()
    }

    fn def(&mut self, n: &LinkedNode, kind: &'static str, scope: std::ops::Range<usize>, top: bool) {
        let d = BDef { name: self.text(n), range: self.r16(n.range()), kind, scope: self.r16(scope), top, implicit: false };
        self.out.defs.push(d);
    }

    /// Defines every name a pattern binds: `x`, `(a, b)`, `(a, ..rest)`, `(key: pat)`. `params`: a `Named` is `name: default`.
    fn pattern(&mut self, n: &LinkedNode, kind: &'static str, scope: std::ops::Range<usize>, top: bool, params: bool) {
        match n.kind() {
            SyntaxKind::Ident => self.def(n, kind, scope, top),
            SyntaxKind::Destructuring | SyntaxKind::Parenthesized | SyntaxKind::Spread | SyntaxKind::Params => {
                for c in significant(n) {
                    self.pattern(&c, kind, scope.clone(), top, params);
                }
            }
            SyntaxKind::Named => {
                let kids = significant(n);
                if params {
                    if let Some(k) = kids.first().filter(|k| k.kind() == SyntaxKind::Ident) {
                        self.def(k, kind, scope, top);
                    }
                } else if let Some(v) = kids.last().filter(|v| v.kind() != SyntaxKind::Colon) {
                    self.pattern(v, kind, scope, top, params);
                }
            }
            _ => {}
        }
    }

    fn walk(&mut self, n: &LinkedNode, end: usize) {
        match n.kind() {
            SyntaxKind::Ident | SyntaxKind::MathIdent => {
                let u = BUse { name: self.text(n), range: self.r16(n.range()) };
                self.out.uses.push(u);
            }
            SyntaxKind::FieldAccess => {
                let kids = significant(n);
                let field = kids.last().filter(|f| kids.len() >= 3 && is_ident(f.kind()));
                for k in &kids {
                    if field.is_some_and(|f| f.range() == k.range()) {
                        continue;
                    }
                    self.walk(k, end);
                }
                if let (Some(t), Some(f)) = (kids.first().filter(|t| is_ident(t.kind())), field) {
                    let b = BField { module: self.text(t), name: self.text(f), range: self.r16(f.range()) };
                    self.out.fields.push(b);
                }
            }
            SyntaxKind::Named => {
                let mut skipped = false;
                for k in significant(n) {
                    if !skipped && is_ident(k.kind()) {
                        skipped = true;
                        continue;
                    }
                    self.walk(&k, end);
                }
            }
            SyntaxKind::CodeBlock | SyntaxKind::ContentBlock | SyntaxKind::Equation => {
                let e = n.range().end;
                for c in n.children() {
                    self.walk(&c, e);
                }
            }
            SyntaxKind::LetBinding => self.let_binding(n, end),
            SyntaxKind::Closure => self.closure(n, end),
            SyntaxKind::ForLoop => {
                let kids = significant(n);
                let at_in = kids.iter().position(|k| k.kind() == SyntaxKind::In);
                let pattern = kids.iter().skip(1).find(|k| k.kind() != SyntaxKind::In);
                let body = kids.last();
                for (i, k) in kids.iter().enumerate() {
                    if at_in.is_some_and(|p| i > p) && Some(k.range()) != body.map(|b| b.range()) {
                        self.walk(k, end);
                    }
                }
                if let (Some(p), Some(b)) = (pattern, body) {
                    self.pattern(p, "let", b.range(), false, false);
                    self.walk(b, end);
                }
            }
            SyntaxKind::ModuleImport => self.import(n, end),
            _ => {
                for c in n.children() {
                    self.walk(&c, end);
                }
            }
        }
    }

    fn let_binding(&mut self, n: &LinkedNode, end: usize) {
        let top = n.parent().is_some_and(|p| p.kind() == SyntaxKind::Markup && p.parent().is_none());
        let kids = significant(n);
        let at_eq = kids.iter().position(|k| k.kind() == SyntaxKind::Eq);
        let named = kids.iter().find_map(|c| {
            let inner = significant(c);
            let name = inner.first().filter(|x| c.kind() == SyntaxKind::Closure && x.kind() == SyntaxKind::Ident && inner.get(1).is_some_and(|y| y.kind() == SyntaxKind::Params));
            name.map(|x| (c.clone(), x.clone()))
        });
        if let Some((c, name)) = named {
            self.def(&name, "func", n.range().start..end, top);
            self.closure(&c, end);
            return;
        }
        let pattern = kids.iter().skip(1).find(|k| k.kind() != SyntaxKind::Eq);
        for (i, k) in kids.iter().enumerate() {
            if at_eq.is_some_and(|p| i > p) {
                self.walk(k, end);
            }
        }
        if let Some(p) = pattern {
            self.pattern(p, "let", n.range().end..end, top, false);
        }
    }

    fn closure(&mut self, n: &LinkedNode, end: usize) {
        let kids = significant(n);
        let params = kids.iter().find(|k| k.kind() == SyntaxKind::Params);
        let body = kids.last().filter(|b| !matches!(b.kind(), SyntaxKind::Params | SyntaxKind::Eq | SyntaxKind::Arrow));
        let scope = body.map_or(n.range().end..n.range().end, |b| b.range().start..n.range().end);
        if let Some(ps) = params {
            for p in significant(ps) {
                if p.kind() == SyntaxKind::Named {
                    // `name: default`: the default is evaluated outside the parameters.
                    for d in significant(&p).iter().skip(1) {
                        self.walk(d, end);
                    }
                }
                self.pattern(&p, "param", scope.clone(), false, true);
            }
        }
        if let Some(b) = body {
            self.walk(b, end);
        }
    }

    fn import(&mut self, n: &LinkedNode, end: usize) {
        let top = n.parent().is_some_and(|p| p.kind() == SyntaxKind::Markup && p.parent().is_none());
        let kids = significant(n);
        let scope = n.range().end..end;
        let mut imp = BImport { path: String::new(), path_range: [0, 0], items: vec![], wildcard: false, scope: self.r16(scope.clone()), module_alias: None };
        let mut literal = false;
        let mut after_as = false;
        let mut alias: Option<LinkedNode> = None;
        for (i, k) in kids.iter().enumerate() {
            match k.kind() {
                SyntaxKind::Import | SyntaxKind::Colon => {}
                SyntaxKind::Str if i == 1 => {
                    literal = true;
                    imp.path = k.cast::<ast::Str>().map(|s| s.get().to_string()).unwrap_or_default();
                    imp.path_range = self.r16(k.range());
                }
                SyntaxKind::As => after_as = true,
                SyntaxKind::Ident if after_as => alias = Some(k.clone()),
                SyntaxKind::Star => imp.wildcard = true,
                SyntaxKind::ImportItems => {
                    for item in significant(k) {
                        let (path, new_name) = match item.kind() {
                            SyntaxKind::ImportItemPath => (Some(item.clone()), None),
                            SyntaxKind::RenamedImportItem => {
                                let inner = significant(&item);
                                (inner.iter().find(|c| c.kind() == SyntaxKind::ImportItemPath).cloned(), inner.iter().rev().find(|c| c.kind() == SyntaxKind::Ident).cloned())
                            }
                            _ => continue,
                        };
                        let Some(name) = path.and_then(|p| significant(&p).into_iter().filter(|c| c.kind() == SyntaxKind::Ident).last()) else { continue };
                        imp.items.push(BItem {
                            name: self.text(&name),
                            name_range: self.r16(name.range()),
                            alias: new_name.as_ref().map(|a| self.text(a)),
                            alias_range: new_name.as_ref().map(|a| self.r16(a.range())),
                        });
                        match &new_name {
                            Some(a) => self.def(a, "alias", scope.clone(), top),
                            None => self.def(&name, "import", scope.clone(), top),
                        }
                    }
                }
                _ if i >= 1 => self.walk(k, end),
                _ => {}
            }
        }
        if let Some(a) = &alias {
            imp.module_alias = Some(BAlias { name: self.text(a), range: self.r16(a.range()) });
            self.def(a, "module", scope.clone(), top);
        } else if literal && imp.items.is_empty() && !imp.wildcard {
            // `import "a.typ"` binds the file's stem.
            let stem = imp.path.rsplit('/').next().unwrap_or("").split(':').next().unwrap_or("").trim_end_matches(".typ").to_string();
            if !stem.is_empty() {
                imp.module_alias = Some(BAlias { name: stem.clone(), range: imp.path_range });
                self.out.defs.push(BDef { name: stem, range: imp.path_range, kind: "module", scope: imp.scope, top, implicit: true });
            }
        }
        if literal {
            self.out.imports.push(imp);
        }
    }
}

/// The definitions, uses and imports of one file as JSON (UTF-16 ranges; see `Bindings`). Thread-safe, no world.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_syntax_bindings(text: TbStr) -> TbBytes {
    let Some(text) = (unsafe { text.get() }) else { return NULL_BYTES };
    let src = Source::detached(text);
    let mut b = Binder { src: &src, out: Bindings::default() };
    let root = LinkedNode::new(src.root());
    stacker::grow(32 << 20, || b.walk(&root, src.text().len()));
    to_bytes(serde_json::to_vec(&b.out).unwrap_or_default())
}

#[derive(Serialize)]
struct Formatted {
    start: u32,
    end: u32,
    text: String,
}

/// Formats the whole text or the nodes covering a UTF-16 range with typstyle; JSON `Formatted` (the replaced
/// UTF-16 range and its new text). Empty on syntax errors or other failure. Thread-safe, no world.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_format(text: TbStr, start16: u32, end16: u32, whole: bool, width: u32, indent: u32) -> TbBytes {
    let Some(text) = (unsafe { text.get() }) else { return NULL_BYTES };
    let src = Source::detached(text);
    let cfg = typstyle_core::Config::new().with_width(width as usize).with_tab_spaces(indent as usize);
    let ts = typstyle_core::Typstyle::new(cfg);
    let out = stacker::grow(32 << 20, || {
        let lines = src.lines();
        if whole {
            let text = ts.format_source(src.clone()).render().ok()?;
            Some(Formatted { start: 0, end: lines.len_utf16() as u32, text })
        } else {
            let r = byte_window(lines, start16, end16);
            let res = ts.format_source_range(src.clone(), r).ok()?;
            let to16 = |b: usize| lines.byte_to_utf16(b.min(lines.len_bytes()));
            Some(Formatted { start: to16(res.source_range.start)? as u32, end: to16(res.source_range.end)? as u32, text: res.content })
        }
    });
    let Some(out) = out else { return NULL_BYTES };
    to_bytes(serde_json::to_vec(&out).unwrap_or_default())
}

// ---- Signature help ----

#[derive(Serialize)]
struct SigParam {
    label: String,
    name: String,
    docs: String,
    positional: bool,
    named: bool,
    variadic: bool,
}

#[derive(Serialize)]
struct SignatureHelp {
    name: String,
    params: Vec<SigParam>,
    /// The parameter the argument at the cursor fills, if any.
    active: Option<usize>,
}

/// Signature help: the function whose argument list `(..)` holds `cursor16` in overlay `path`, every parameter, and
/// the one the argument at the cursor fills. Nothing inside a content block (also not a trailing `[..]` argument).
/// JSON `{name, params: [{label, name, docs, positional, named, variadic}], active}`; null bytes if none.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_world_signature_help(w: *mut TbWorld, path: TbStr, cursor16: u32) -> TbBytes {
    let w = unsafe { &*w };
    let Some(src) = unsafe { path.get() }.and_then(project_id).and_then(|id| w.overlays.get(&id)) else { return NULL_BYTES };
    let lines = src.lines();
    let u = cursor16 as usize;
    let Some(cursor) = lines.utf16_to_byte(u).filter(|&b| lines.byte_to_utf16(b) == Some(u)) else { return NULL_BYTES };
    match stacker::grow(32 << 20, || signature_help(w, src, cursor)) {
        Some(h) => to_bytes(serde_json::to_vec(&h).unwrap_or_default()),
        None => NULL_BYTES,
    }
}

fn signature_help(w: &TbWorld, src: &Source, cursor: usize) -> Option<SignatureHelp> {
    let root = LinkedNode::new(src.root());
    // The innermost argument list whose parentheses hold the cursor; markup (a content block) on the way ends the search.
    let mut node = root.leaf_at(cursor, Side::Before);
    let args = loop {
        let n = node?;
        match n.kind() {
            SyntaxKind::Args => {
                let open = n.children().find(|c| c.kind() == SyntaxKind::LeftParen)?;
                let close = n.children().find(|c| c.kind() == SyntaxKind::RightParen);
                if open.range().end <= cursor && close.is_none_or(|c| cursor <= c.range().start) { break n }
                return None;
            }
            SyntaxKind::Markup => return None,
            _ => {}
        }
        node = n.parent().cloned();
    };
    let call = args.parent()?.clone();
    if call.kind() != SyntaxKind::FuncCall { return None }
    let func = callee_func(w, src, &call.children().next()?)?;

    // Which argument the cursor is in: the commas before it, and the positional arguments in the slots before that one.
    let slot_of_cursor = args.children()
        .take_while(|c| c.kind() != SyntaxKind::RightParen)
        .filter(|c| c.kind() == SyntaxKind::Comma && c.range().end <= cursor)
        .count();
    let (mut slot, mut positional_before, mut current) = (0, 0, None);
    for c in args.children() {
        match c.kind() {
            SyntaxKind::LeftParen => continue,
            SyntaxKind::RightParen => break,
            SyntaxKind::Comma => { slot += 1; continue }
            k if k.is_trivia() => continue,
            _ => {}
        }
        if slot < slot_of_cursor && !matches!(c.kind(), SyntaxKind::Named | SyntaxKind::Spread) { positional_before += 1 }
        if slot == slot_of_cursor { current = Some(c.clone()) }
    }

    use typst::foundations::{ClosureParamInfo, ParamInfo};
    let params: Vec<SigParam> = func.params().map(|p| {
        let label = param_label(&p);
        let (name, docs, positional, named, variadic) = match &p {
            ParamInfo::Native(n) => (n.name.to_string(), n.docs.to_string(), n.positional, n.named, n.variadic),
            ParamInfo::Closure(c) => match &c.v {
                ClosureParamInfo::Pos { name } => (name.as_ref().map_or_else(String::new, |n| n.to_string()), String::new(), true, false, false),
                ClosureParamInfo::Sink { name } => (name.as_ref().map_or_else(String::new, |n| n.to_string()), String::new(), true, false, true),
                ClosureParamInfo::Named { name, .. } => (name.to_string(), String::new(), false, true, false),
            },
            ParamInfo::Plugin => ("args".to_string(), String::new(), true, false, true),
        };
        SigParam { label, name, docs, positional, named, variadic }
    }).collect();

    let named_arg = current.as_ref().and_then(|c| c.cast::<ast::Named>()).map(|n| n.name().get().to_string());
    let active = match named_arg {
        Some(name) => params.iter().position(|p| p.named && p.name == name),
        None => {
            let positional: Vec<usize> = params.iter().enumerate().filter(|(_, p)| p.positional).map(|(i, _)| i).collect();
            positional.get(positional_before).copied()
                .or_else(|| positional.last().copied().filter(|&i| params[i].variadic))
        }
    };
    Some(SignatureHelp { name: func.name().unwrap_or("function").to_string(), params, active })
}

/// The function a call's callee names: a project or package function, a built-in, a module field (`calc.max`),
/// or a type's constructor (`str(..)`).
fn callee_func(w: &TbWorld, src: &Source, callee: &LinkedNode) -> Option<typst::foundations::Func> {
    let as_func = |v: Value| match v {
        Value::Func(f) => Some(f),
        Value::Type(t) => t.constructor().ok(),
        _ => None,
    };
    typst_ide::analyze_expr(w, callee).into_iter().find_map(|(v, _)| as_func(v))
        .or_else(|| match typst_ide::definition(w, w.last_doc.as_ref(), src, callee.range().end, Side::Before)? {
            typst_ide::Definition::Std(v) => as_func(v),
            _ => None,
        })
        .or_else(|| as_func(std_field_at(w, src, callee.range().end)?.1))
}

// ---- Tables (parse for the visual editor) ----

struct TableArg {
    name: String,
    value: String,
    shape: u8,
    items: Vec<String>,
}

struct TableCell {
    kind: u8,
    source: String,
    inner: String,
}

struct TableHeader {
    args: Vec<TableArg>,
    cells: Vec<TableCell>,
}

pub struct TbTable {
    unsupported: String,
    range: TbRange16,
    callee: String,
    args: Vec<TableArg>,
    header: Option<TableHeader>,
    cells: Vec<TableCell>,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct TbTableArg {
    name: TbStr,
    value: TbStr,
    shape: u8,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct TbTableCell {
    kind: u8,
    source: TbStr,
    inner: TbStr,
}

const ALIGN_WORDS: [&str; 9] = ["left", "center", "right", "start", "end", "top", "horizon", "bottom", "auto"];

fn is_align(n: &LinkedNode, text: &str) -> bool {
    match n.kind() {
        SyntaxKind::Ident => ALIGN_WORDS.contains(&&text[n.range()]),
        SyntaxKind::Binary => n.children().all(|c| c.kind().is_trivia() || c.kind() == SyntaxKind::Plus || is_align(&c, text)),
        _ => false,
    }
}

/// Shape of a named argument's value: 0 other, 1 integer, 2 array literal, 3 single alignment. An `align`
/// array of anything but alignments is "other" so the editor leaves it alone.
fn table_arg(text: &str, named: &LinkedNode) -> TableArg {
    let name = named.children().next().map(|n| text[n.range()].to_string()).unwrap_or_default();
    let Some(v) = named.children().last() else {
        return TableArg { name, value: String::new(), shape: 0, items: vec![] };
    };
    let mut items = vec![];
    let mut spread = false;
    let shape = match v.kind() {
        SyntaxKind::Int => 1,
        SyntaxKind::Array => {
            for c in v.children() {
                match c.kind() {
                    SyntaxKind::LeftParen | SyntaxKind::RightParen | SyntaxKind::Comma => {}
                    k if k.is_trivia() => {}
                    k => {
                        spread |= k == SyntaxKind::Spread;
                        items.push(text[c.range()].to_string());
                    }
                }
            }
            let plain = v.children().filter(|c| !matches!(c.kind(), SyntaxKind::LeftParen | SyntaxKind::RightParen | SyntaxKind::Comma) && !c.kind().is_trivia());
            let all_align = plain.into_iter().all(|c| is_align(&c, text));
            if spread || (name == "align" && !all_align) { 0 } else { 2 }
        }
        _ if is_align(&v, text) => 3,
        _ => 0,
    };
    TableArg { name, value: text[v.range()].to_string(), shape, items: if shape == 2 { items } else { vec![] } }
}

fn has_error(n: &SyntaxNode) -> bool {
    n.kind() == SyntaxKind::Error || n.children().any(has_error)
}

/// `table.header` on the callee `table`: the field name, if `n` is a call of such a field access.
fn table_field(n: &LinkedNode, text: &str, callee: &str) -> Option<String> {
    let f = n.children().next().filter(|f| f.kind() == SyntaxKind::FieldAccess)?;
    let mut parts = f.children().filter(|c| c.kind() == SyntaxKind::Ident);
    let (target, field) = (parts.next()?, parts.last()?);
    (&text[target.range()] == callee).then(|| text[field.range()].to_string())
}

fn table_cell(text: &str, n: &LinkedNode, callee: &str) -> Result<TableCell, String> {
    let r = n.range();
    let source = text[r.clone()].to_string();
    if n.kind() == SyntaxKind::ContentBlock {
        return Ok(TableCell { kind: 0, inner: text[r.start + 1..r.end - 1].to_string(), source });
    }
    if n.kind() == SyntaxKind::FuncCall {
        match table_field(n, text, callee).as_deref() {
            Some("cell") => {
                let placed = n.children().last().is_some_and(|args| {
                    args.children().filter(|c| c.kind() == SyntaxKind::Named).any(|c| {
                        c.children().next().is_some_and(|k| matches!(&text[k.range()], "colspan" | "rowspan" | "x" | "y"))
                    })
                });
                if placed {
                    return Err(format!("{callee}.cell(...) with colspan, rowspan, x or y places cells by hand"));
                }
            }
            Some("hline" | "vline") => return Err(format!("{callee} lines ({callee}.hline, {callee}.vline) can't be edited visually")),
            Some("footer") => return Err(format!("{callee}.footer can't be edited visually")),
            _ => {}
        }
    }
    Ok(TableCell { kind: 1, inner: format!("#{source}"), source })
}

const TRAILING: &str = "content blocks after the closing parenthesis can't be edited visually";

/// Named args, cells and the header of one argument list (the call's own, or `table.header`'s).
fn table_args(text: &str, args: &LinkedNode, callee: &str, in_header: bool) -> Result<(Vec<TableArg>, Vec<TableCell>, Option<TableHeader>), String> {
    let (mut named, mut cells, mut header, mut closed) = (vec![], vec![], None, false);
    for c in args.children() {
        match c.kind() {
            SyntaxKind::LeftParen | SyntaxKind::Comma | SyntaxKind::Space | SyntaxKind::Parbreak => {}
            SyntaxKind::RightParen => closed = true,
            SyntaxKind::LineComment | SyntaxKind::BlockComment => return Err("comments between the arguments would be lost".into()),
            _ if closed => return Err(TRAILING.into()),
            SyntaxKind::Named => named.push(table_arg(text, &c)),
            SyntaxKind::Spread => return Err("spread arguments (..) can't be edited visually".into()),
            _ => {
                if c.kind() == SyntaxKind::FuncCall && table_field(&c, text, callee).as_deref() == Some("header") {
                    if in_header || header.is_some() {
                        return Err(format!("more than one {callee}.header"));
                    }
                    if !cells.is_empty() {
                        return Err(format!("{callee}.header is not the first row"));
                    }
                    let inner = c.children().last().ok_or("unreadable header")?;
                    let (args, cells, _) = table_args(text, &inner, callee, true)?;
                    header = Some(TableHeader { args, cells });
                } else {
                    cells.push(table_cell(text, &c, callee)?);
                }
            }
        }
    }
    if !closed {
        return Err(TRAILING.into());
    }
    Ok((named, cells, header))
}

fn parse_table(src: &Source, call: &LinkedNode, callee: &str) -> TbTable {
    let (text, lines) = (src.text(), src.lines());
    let r = call.range();
    let to16 = |b: usize| lines.byte_to_utf16(b).unwrap_or(0) as u32;
    let mut t = TbTable {
        unsupported: String::new(),
        range: TbRange16 { start: to16(r.start), end: to16(r.end) },
        callee: callee.to_string(),
        args: vec![],
        header: None,
        cells: vec![],
    };
    let parsed = (|| {
        if has_error(call.get()) {
            return Err("the table has a syntax error".to_string());
        }
        let args = call.children().last().filter(|a| a.kind() == SyntaxKind::Args).ok_or("unreadable arguments")?;
        let (named, cells, header) = table_args(text, &args, callee, false)?;
        // Typst counts an array's length or the integer; no `columns` and `()` both make one column.
        let columns = match named.iter().find(|a| a.name == "columns") {
            None => 1,
            Some(a) if a.shape == 1 => a.value.parse::<usize>().map_err(|_| "`columns:` is too large".to_string())?.max(1),
            Some(a) if a.shape == 2 => a.items.len().max(1),
            Some(_) => return Err("`columns:` must be a whole number or a plain array like (1fr, auto)".to_string()),
        };
        if let Some(h) = &header
            && h.cells.len() != columns
        {
            return Err(format!("the header has {} cells, not one row of {columns}", h.cells.len()));
        }
        let total = cells.len() + header.as_ref().map_or(0, |h| h.cells.len());
        if total % columns != 0 {
            return Err(format!("{total} cells don't fill whole rows of {columns} columns"));
        }
        Ok((named, cells, header))
    })();
    match parsed {
        Ok((named, cells, header)) => (t.args, t.cells, t.header) = (named, cells, header),
        Err(reason) => t.unsupported = reason,
    }
    t
}

/// The innermost `table(...)` or `grid(...)` call that contains the caret, with or without `#`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_syntax_table_at(s: *const TbSyntax, cursor16: u32) -> *mut TbTable {
    let src = &unsafe { &*s }.source;
    let text = src.text();
    let Some(byte) = src.lines().utf16_to_byte(cursor16 as usize) else { return std::ptr::null_mut() };
    let root = LinkedNode::new(src.root());
    for side in [Side::Before, Side::After] {
        let mut node = root.leaf_at(byte, side);
        while let Some(n) = node {
            let r = n.range();
            if n.kind() == SyntaxKind::FuncCall && r.start <= byte && byte <= r.end {
                let callee = n.children().next().filter(|c| c.kind() == SyntaxKind::Ident).map(|c| &text[c.range()]);
                if let Some(name @ ("table" | "grid")) = callee {
                    return Box::into_raw(Box::new(parse_table(src, &n, name)));
                }
            }
            node = n.parent().cloned();
        }
    }
    std::ptr::null_mut()
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_table_unsupported(t: *const TbTable) -> TbStr {
    TbStr::of(&unsafe { &*t }.unsupported)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_table_range(t: *const TbTable) -> TbRange16 {
    unsafe { &*t }.range
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_table_callee(t: *const TbTable) -> TbStr {
    TbStr::of(&unsafe { &*t }.callee)
}

fn arg_out(a: &TableArg) -> TbTableArg {
    TbTableArg { name: TbStr::of(&a.name), value: TbStr::of(&a.value), shape: a.shape }
}

fn cell_out(c: &TableCell) -> TbTableCell {
    TbTableCell { kind: c.kind, source: TbStr::of(&c.source), inner: TbStr::of(&c.inner) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_table_arg_count(t: *const TbTable) -> u32 {
    unsafe { &*t }.args.len() as u32
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_table_arg(t: *const TbTable, i: u32) -> TbTableArg {
    arg_out(&unsafe { &*t }.args[i as usize])
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_table_arg_item_count(t: *const TbTable, arg: u32) -> u32 {
    unsafe { &*t }.args[arg as usize].items.len() as u32
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_table_arg_item(t: *const TbTable, arg: u32, i: u32) -> TbStr {
    TbStr::of(&unsafe { &*t }.args[arg as usize].items[i as usize])
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_table_has_header(t: *const TbTable) -> bool {
    unsafe { &*t }.header.is_some()
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_table_header_arg_count(t: *const TbTable) -> u32 {
    unsafe { &*t }.header.as_ref().map_or(0, |h| h.args.len() as u32)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_table_header_arg(t: *const TbTable, i: u32) -> TbTableArg {
    arg_out(&unsafe { &*t }.header.as_ref().unwrap().args[i as usize])
}

/// Header cells (`header` true) or body cells.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_table_cell_count(t: *const TbTable, header: bool) -> u32 {
    let t = unsafe { &*t };
    (if header { t.header.as_ref().map_or(0, |h| h.cells.len()) } else { t.cells.len() }) as u32
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_table_cell(t: *const TbTable, header: bool, i: u32) -> TbTableCell {
    let t = unsafe { &*t };
    cell_out(if header { &t.header.as_ref().unwrap().cells[i as usize] } else { &t.cells[i as usize] })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_table_free(t: *mut TbTable) {
    if !t.is_null() {
        drop(unsafe { Box::from_raw(t) });
    }
}

// ---- Outline ----

#[repr(C)]
pub struct TbHeading {
    level: u32,
    numbering: TbStr,
    title: TbStr,
    page: u32,
    y_pt: f32,
    path: TbStr,
    utf16_offset: u32,
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_snapshot_outline_count(s: *const TbSnapshot) -> u32 {
    unsafe { &*s }.outline.len() as u32
}

/// Headings of the snapshot's document (empty if the compile failed). `page` is 0-based, `y_pt` from the page top.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_snapshot_outline(s: *const TbSnapshot, i: u32) -> TbHeading {
    match unsafe { &*s }.outline.get(i as usize) {
        Some(h) => TbHeading {
            level: h.level,
            numbering: TbStr::of(&h.numbering),
            title: TbStr::of(&h.title),
            page: h.page,
            y_pt: h.y_pt,
            path: TbStr::of(&h.path),
            utf16_offset: h.offset16,
        },
        None => TbHeading { level: 0, numbering: NULL_STR, title: NULL_STR, page: 0, y_pt: 0.0, path: NULL_STR, utf16_offset: 0 },
    }
}

// ---- Symbols ----

#[repr(C)]
pub struct TbSymbol {
    name: TbStr,
    text: TbStr,
    emoji: bool,
}

fn collect_symbols(prefix: &str, module: &typst::foundations::Module, emoji: bool, out: &mut Vec<(String, String, bool)>) {
    for (name, binding) in module.scope().iter() {
        let full = format!("{prefix}{name}");
        match binding.read() {
            Value::Symbol(sym) => {
                for (mods, text, deprecated) in sym.variants() {
                    if deprecated.is_some() {
                        continue;
                    }
                    let mut n = full.clone();
                    for m in mods.iter() {
                        n.push('.');
                        n.push_str(m);
                    }
                    out.push((n, text.to_string(), emoji));
                }
            }
            Value::Module(m) => collect_symbols(&format!("{full}."), m, emoji, out),
            _ => {}
        }
    }
}

fn symbols() -> &'static [(String, String, bool)] {
    static LIST: std::sync::OnceLock<Vec<(String, String, bool)>> = std::sync::OnceLock::new();
    LIST.get_or_init(|| {
        let lib = Library::default();
        let mut out = Vec::new();
        for (module, emoji) in [("sym", false), ("emoji", true)] {
            if let Some(Value::Module(m)) = lib.global.scope().get(module).map(|b| b.read()) {
                collect_symbols("", m, emoji, &mut out);
            }
        }
        out
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn tb_symbol_count() -> u32 {
    symbols().len() as u32
}

/// Symbol `i` of `sym` then `emoji`: name relative to its module (`arrow.r.long`) and its character(s). Static storage.
#[unsafe(no_mangle)]
pub extern "C" fn tb_symbol(i: u32) -> TbSymbol {
    match symbols().get(i as usize) {
        Some((n, t, e)) => TbSymbol { name: TbStr::of(n), text: TbStr::of(t), emoji: *e },
        None => TbSymbol { name: NULL_STR, text: NULL_STR, emoji: false },
    }
}

// ---- Bibliography (hayagriva) ----

#[repr(C)]
pub struct TbBibEntry {
    key: TbStr,
    title: TbStr,
    authors: TbStr,
    year: i32,
    has_year: bool,
    kind: TbStr,
}

struct OwnedBibEntry {
    key: String,
    title: String,
    authors: String,
    year: Option<i32>,
    kind: String,
}

pub struct TbBib {
    error: String,
    entries: Vec<OwnedBibEntry>,
}

/// Parses BibLaTeX (`yaml` false) or hayagriva YAML text with the same crate typst uses. A parse failure
/// yields no entries and a non-empty error. Never NULL.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_bibliography(text: TbStr, yaml: bool) -> *mut TbBib {
    let Some(text) = (unsafe { text.get() }) else {
        return Box::into_raw(Box::new(TbBib { error: "not valid UTF-8".into(), entries: Vec::new() }));
    };
    let parsed = if yaml {
        hayagriva::io::from_yaml_str(text).map_err(|e| e.to_string())
    } else {
        hayagriva::io::from_biblatex_str(text)
            .map_err(|es| es.iter().map(|e| e.to_string()).collect::<Vec<_>>().join("\n"))
    };
    let bib = match parsed {
        Ok(lib) => TbBib {
            error: String::new(),
            entries: lib
                .iter()
                .map(|e| OwnedBibEntry {
                    key: e.key().to_string(),
                    title: e.title().map(|t| t.to_string()).unwrap_or_default(),
                    authors: e
                        .authors()
                        .map(|a| a.iter().map(|p| p.given_first(false)).collect::<Vec<_>>().join(", "))
                        .unwrap_or_default(),
                    year: e.date_any().map(|d| d.year),
                    kind: format!("{:?}", e.entry_type()),
                })
                .collect(),
        },
        Err(error) => TbBib { error, entries: Vec::new() },
    };
    Box::into_raw(Box::new(bib))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_bib_error(b: *const TbBib) -> TbStr {
    TbStr::of(&unsafe { &*b }.error)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_bib_count(b: *const TbBib) -> u32 {
    unsafe { &*b }.entries.len() as u32
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_bib_entry(b: *const TbBib, i: u32) -> TbBibEntry {
    match unsafe { &*b }.entries.get(i as usize) {
        Some(e) => TbBibEntry {
            key: TbStr::of(&e.key),
            title: TbStr::of(&e.title),
            authors: TbStr::of(&e.authors),
            year: e.year.unwrap_or(0),
            has_year: e.year.is_some(),
            kind: TbStr::of(&e.kind),
        },
        None => TbBibEntry { key: NULL_STR, title: NULL_STR, authors: NULL_STR, year: 0, has_year: false, kind: NULL_STR },
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn tb_bib_free(b: *mut TbBib) {
    if !b.is_null() {
        drop(unsafe { Box::from_raw(b) });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn bindings(text: &str) -> serde_json::Value {
        let src = Source::detached(text);
        let mut b = Binder { src: &src, out: Bindings::default() };
        b.walk(&LinkedNode::new(src.root()), text.len());
        serde_json::to_value(&b.out).unwrap()
    }

    #[test]
    fn dump() {
        for t in [
            "$ f(x) + a.b $\n#let f(x, y: 2) = x + y\n#let g = z => z + f(1, y: 3)\n#for (k, v) in d [#k]\n#import \"a.typ\": h, i as j\n#import \"../l/m.typ\" as mm\n#import \"n.typ\": *\n#import \"o.typ\"\n#mm.h #o.x $ f(x) $",
        ] {
            println!("{}", serde_json::to_string_pretty(&bindings(t)).unwrap());
        }
    }
}
