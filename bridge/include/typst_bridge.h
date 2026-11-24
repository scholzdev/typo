#ifndef TYPST_BRIDGE_H
#define TYPST_BRIDGE_H
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

typedef struct { const uint8_t *ptr; size_t len; } TbStr;   // borrowed UTF-8, not NUL-terminated
typedef struct { uint8_t *ptr; size_t len; } TbBytes;       // Rust-owned; release with tb_bytes_free

typedef struct TbRuntime  TbRuntime;
typedef struct TbWorld    TbWorld;
typedef struct TbSnapshot TbSnapshot;

TbRuntime *tb_runtime_new(const TbStr *font_paths, size_t font_path_count,
                          TbStr font_index_path, TbStr package_cache_dir);
void tb_runtime_free(TbRuntime *);
// Replaces the @preview package list (official index JSON); returns the number of compatible entries kept.
size_t tb_runtime_set_package_index(const TbRuntime *, TbStr json);
// JSON array (UTF-8) of the Universe template packages of the index last applied: only compatible entries
// with a `template` object, one per name at its highest compatible version, sorted by name. Elements:
// {"name","version","description","authors":[..],"categories":[..],"path","entrypoint"}. "[]" before any index.
TbBytes tb_runtime_templates(const TbRuntime *);
// Resolves `spec` (e.g. "@preview/charged-ieee:0.1.4") as a world does: user packages dir, cache, then a
// blocking download from Universe into the cache. *ok true: the bytes are the absolute package directory;
// false: a human-readable error. Never call on the main thread.
TbBytes tb_runtime_fetch_package(const TbRuntime *, TbStr spec, bool *ok);
// Sets the user's packages data dir (<ns>/<name>/<version>/typst.toml; empty clears it). Worlds use it from
// their next compile or completion on. Returns the number of compatible packages found there now.
size_t tb_runtime_set_packages_dir(const TbRuntime *, TbStr dir);

typedef void (*TbDownloadFn)(void *ctx, TbStr package_spec);
TbWorld *tb_world_new(const TbRuntime *, TbStr root_dir, TbStr main_path,
                      TbDownloadFn on_download, void *ctx);
// Replaces the project's font files (absolute paths); their families win over system fonts of the same name.
void tb_world_set_project_fonts(TbWorld *, const TbStr *paths, size_t count);
void tb_world_set_main(TbWorld *, TbStr path);
void tb_world_set_text(TbWorld *, TbStr path, TbStr text);
bool tb_world_edit(TbWorld *, TbStr path, uint32_t utf16_start, uint32_t utf16_end,
                   TbStr replacement, uint32_t expected_len);
TbSnapshot *tb_world_compile(TbWorld *);
void tb_world_free(TbWorld *);

// Moves an overlay to a new path with the same text; false (nothing changed) if `old` has no overlay.
bool tb_world_relocate_overlay(TbWorld *, TbStr old_path, TbStr new_path);

// Drops an overlay; the next compile reads the path from disk.
void tb_world_remove_overlay(TbWorld *, TbStr path);

// Test support: the overlay text of `path`, ptr NULL if there is no overlay.
TbBytes tb_world_text(const TbWorld *, TbStr path);

typedef struct { uint64_t hash_hi, hash_lo; float width_pt, height_pt; } TbPage;
enum { TB_ERROR = 0, TB_WARNING = 1 };
enum { TB_DETACHED = 0, TB_PROJECT = 1, TB_PACKAGE = 2 };
typedef struct {
    uint8_t severity, origin;
    TbStr path;
    uint32_t utf16_start, utf16_end;
    TbStr message;
    TbStr hints;
} TbDiagnostic;
uint32_t     tb_snapshot_page_count(const TbSnapshot *);
TbPage       tb_snapshot_page(const TbSnapshot *, uint32_t index);
uint32_t     tb_snapshot_diagnostic_count(const TbSnapshot *);
TbDiagnostic tb_snapshot_diagnostic(const TbSnapshot *, uint32_t index);
// Words of the compiled document by Unicode word segmentation over all page text; 0 if it has no document.
// Computed on each call (not during the compile); the snapshot is immutable, so any thread may call it.
uint32_t tb_snapshot_word_count(const TbSnapshot *);
uint32_t tb_text_word_count(TbStr text);                // the same segmentation over source text
TbBytes tb_snapshot_render(const TbSnapshot *, uint32_t page, float pixel_per_pt,
                           uint32_t *width, uint32_t *height);
TbBytes tb_snapshot_pdf(const TbSnapshot *);
// standard: 0 plain, 1 PDF/A-2b, 2 PDF/A-3b, 3 PDF/UA-1. On failure *ok is false and the bytes are the readable error.
TbBytes tb_snapshot_export_pdf(const TbSnapshot *, uint8_t standard, const uint32_t *ranges, size_t range_count, bool *ok);
TbBytes tb_snapshot_svg(const TbSnapshot *, uint32_t page);   // UTF-8 SVG; empty on a bad page
// JSON [{"title","level","words","page"}] per heading section (entry 0, level 0: text before the first heading).
TbBytes tb_snapshot_section_words(const TbSnapshot *);
void    tb_snapshot_free(TbSnapshot *);
void    tb_bytes_free(TbBytes);

// Syntax mirror: highlighting and prose ranges, independent of any world.
typedef struct TbSyntax TbSyntax;
typedef struct { uint32_t start, end; } TbRange16;
typedef struct { uint32_t start, end; uint8_t tag; } TbSpan;
TbSyntax *tb_syntax_new(TbStr text);
void      tb_syntax_free(TbSyntax *);
bool      tb_syntax_edit(TbSyntax *, uint32_t start16, uint32_t end16, TbStr replacement,
                         uint32_t expected_len, TbRange16 *dirty);
void      tb_syntax_set_text(TbSyntax *, TbStr text);
size_t    tb_syntax_highlight(const TbSyntax *, uint32_t start16, uint32_t end16, TbSpan *out, size_t cap);
size_t    tb_syntax_prose(const TbSyntax *, uint32_t start16, uint32_t end16, TbRange16 *out, size_t cap);
// The innermost strong (kind 0), emph (1) or `#underline[..]` call (2, including its `#`) containing
// [start16, end16]: a caret strictly inside, or a selection within it. False if there is none.
bool      tb_syntax_enclosing(const TbSyntax *, uint8_t kind, uint32_t start16, uint32_t end16, TbRange16 *out);
// The innermost call arguments around `pos16` with at least `min_targets` arguments whose delimiters hold the
// caret. Writes the Args node to `whole` and one Tab target per argument to `out` (a content block: its inside;
// `name: value`: the value; else the expression); returns the target count (may exceed `cap`), 0 if none.
size_t    tb_syntax_args(const TbSyntax *, uint32_t pos16, uint32_t min_targets, TbRange16 *whole, TbRange16 *out, size_t cap);
// What the caret at a UTF-16 position edits: 0 markup, 1 code, 2 math, 3 string/raw/comment text.
uint8_t   tb_syntax_mode(const TbSyntax *, uint32_t pos16);
// Definitions, uses and imports of one file as JSON (UTF-16 ranges). Thread-safe, independent of any world.
TbBytes   tb_syntax_bindings(TbStr text);
// typstyle: formats the whole text, or the nodes covering a UTF-16 range. JSON {start,end,text} (replaced UTF-16 range); empty on error.
TbBytes   tb_format(TbStr text, uint32_t start16, uint32_t end16, bool whole, uint32_t width, uint32_t indent);

// Completion: typst_ide::autocomplete on overlay `path` at a UTF-16 cursor. NULL if the path has no overlay
// or the cursor is out of range or splits a surrogate. count == 0 means nothing to show.
// Kinds: 0 Syntax, 1 Func, 2 Type, 3 Param, 4 Constant, 5 Path, 6 Package, 7 Label, 8 Font, 9 Symbol.
typedef struct TbCompletions TbCompletions;
typedef struct { uint8_t kind; TbStr label; TbStr apply; TbStr detail; TbStr symbol; } TbCompletion;  // strings borrowed until free; empty = absent
TbCompletions *tb_world_complete(TbWorld *, TbStr path, uint32_t cursor16, bool explicit_);
// Same, but completes `text` as the content of `path` (the overlay is neither read nor changed).
TbCompletions *tb_world_complete_text(TbWorld *, TbStr path, TbStr text, uint32_t cursor16, bool explicit_);
uint32_t       tb_completions_from(const TbCompletions *);   // UTF-16 start of the replaced range [from, cursor)
uint32_t       tb_completions_count(const TbCompletions *);
TbCompletion   tb_completions_get(const TbCompletions *, uint32_t index);
void           tb_completions_free(TbCompletions *);

// Jump between preview and source. Page indices are 0-based here; points are pt from the page's top left.
typedef struct { uint32_t page; float x_pt, y_pt; } TbPosition;
enum { TB_JUMP_NONE = 0, TB_JUMP_FILE = 1, TB_JUMP_URL = 2, TB_JUMP_POSITION = 3 };
typedef struct TbJump TbJump;
// Click on page `click.page` of `shown`, the snapshot the preview displays (not last_doc), resolved against
// the world's current text. NULL if `shown` has no document; a miss is a TbJump of kind NONE.
TbJump    *tb_world_jump_from_click(TbWorld *, const TbSnapshot *shown, TbPosition click);
uint8_t    tb_jump_kind(const TbJump *);
TbStr      tb_jump_path(const TbJump *);       // FILE: project-relative path; empty for package files
uint32_t   tb_jump_offset16(const TbJump *);   // FILE: UTF-16 offset in the world's current text of that file
TbStr      tb_jump_url(const TbJump *);        // URL, borrowed until free
TbPosition tb_jump_position(const TbJump *);   // POSITION
void       tb_jump_free(TbJump *);
// Positions in the last successful document that belong to the leaf at `cursor16` in overlay `path`.
// Writes at most cap, returns the total count (0 if no document, no overlay, or nothing found).
size_t     tb_world_jump_from_cursor(TbWorld *, TbStr path, uint32_t cursor16, TbPosition *out, size_t cap);

// The equation around `cursor16` in overlay `path`, cropped from the last successful document and rendered
// opaque RGBA at pixel_per_pt (reduced for very wide equations). Empty if the file changed since that compile,
// the cursor is not in math, or the equation is not in the document. Writes the equation's UTF-16 range and
// the image's size in pixels and points.
TbBytes    tb_world_equation_image(TbWorld *, TbStr path, uint32_t cursor16, float pixel_per_pt,
                                   uint32_t *width, uint32_t *height, float *width_pt, float *height_pt, TbRange16 *range);

// Hover: typst_ide::tooltip at a UTF-16 cursor (Side::After) in overlay `path`, using the last successful
// document for labels. NULL if nothing to show (no overlay, bad cursor, trivia, no tooltip).
enum { TB_HOVER_TEXT = 1, TB_HOVER_CODE = 2 };
typedef struct TbHover TbHover;
TbHover   *tb_world_hover(TbWorld *, TbStr path, uint32_t cursor16);
uint8_t    tb_hover_kind(const TbHover *);
TbStr      tb_hover_text(const TbHover *);    // TEXT: Markdown prose; CODE: Typst code. Borrowed until free.
TbRange16  tb_hover_range(const TbHover *);   // UTF-16 range of the hovered leaf
void       tb_hover_free(TbHover *);

// Definition: typst_ide::definition at a UTF-16 cursor in overlay `path` (Side::After, then Before), resolved
// through imports and packages; labels use the last successful document. NULL if there is none.
// Kinds: 0 span in the project, 1 file in the project, 2 std, 3 package.
enum { TB_DEF_SPAN = 0, TB_DEF_FILE = 1, TB_DEF_STD = 2, TB_DEF_PACKAGE = 3 };
typedef struct TbDefinition TbDefinition;
TbDefinition *tb_world_definition(TbWorld *, TbStr path, uint32_t cursor16);
uint8_t       tb_definition_kind(const TbDefinition *);
TbStr         tb_definition_path(const TbDefinition *);      // SPAN/FILE: project-relative; PACKAGE: the path inside the package. Borrowed until free.
TbRange16     tb_definition_range16(const TbDefinition *);   // SPAN/PACKAGE-span: UTF-16 range in that file; else 0..0
TbStr         tb_definition_name(const TbDefinition *);      // STD: the item's name; PACKAGE: the package spec
TbStr         tb_definition_docs(const TbDefinition *);      // STD: the item's documentation (Markdown, may be empty). Borrowed until free.
TbStr         tb_definition_url(const TbDefinition *);       // STD: its typst.app documentation page, empty when unknown. Borrowed until free.
TbStr         tb_definition_signature(const TbDefinition *); // the function at the cursor with every parameter and its types; empty otherwise. Borrowed until free.
TbBytes       tb_world_signature_help(TbWorld *, TbStr path, uint32_t cursor16); // JSON {name, params: [{label, name, docs, positional, named, variadic}], active} for the call whose (..) holds the cursor; null bytes if none
void          tb_definition_free(TbDefinition *);

// Tables: the innermost `table(...)` or `grid(...)` call around a UTF-16 caret (with or without `#`, also
// inside `figure(...)`). NULL if there is none. A call the editor cannot round-trip has a non-empty
// `unsupported` reason and nothing else. Strings are borrowed until tb_table_free.
// Arg shapes: 0 other, 1 integer, 2 array literal (items = source of each entry), 3 single alignment.
// Cell kinds: 0 content block (inner = markup inside the brackets), 1 other expression (inner = "#" + source).
typedef struct TbTable TbTable;
typedef struct { TbStr name; TbStr value; uint8_t shape; } TbTableArg;
typedef struct { uint8_t kind; TbStr source; TbStr inner; } TbTableCell;
TbTable    *tb_syntax_table_at(const TbSyntax *, uint32_t cursor16);
TbStr       tb_table_unsupported(const TbTable *);
TbRange16   tb_table_range(const TbTable *);                 // the call, without a leading `#`
TbStr       tb_table_callee(const TbTable *);                // "table" or "grid"
uint32_t    tb_table_arg_count(const TbTable *);             // named args, source order, verbatim
TbTableArg  tb_table_arg(const TbTable *, uint32_t i);
uint32_t    tb_table_arg_item_count(const TbTable *, uint32_t arg);
TbStr       tb_table_arg_item(const TbTable *, uint32_t arg, uint32_t i);
bool        tb_table_has_header(const TbTable *);
uint32_t    tb_table_header_arg_count(const TbTable *);
TbTableArg  tb_table_header_arg(const TbTable *, uint32_t i);
uint32_t    tb_table_cell_count(const TbTable *, bool header);
TbTableCell tb_table_cell(const TbTable *, bool header, uint32_t i);
void        tb_table_free(TbTable *);

// Outline: headings of the snapshot's document (none if it has no document), in document order, only those
// defined in project files. `numbering` is the plain numbering text ("1.2." or empty), `page` is 0-based, `y_pt`
// from the page top, `utf16_offset` into the world's text of `path` when this snapshot was compiled.
typedef struct { uint32_t level; TbStr numbering; TbStr title; uint32_t page; float y_pt; TbStr path; uint32_t utf16_offset; } TbHeading;
uint32_t  tb_snapshot_outline_count(const TbSnapshot *);
TbHeading tb_snapshot_outline(const TbSnapshot *, uint32_t index);

// Symbols of typst's `sym` then `emoji` modules, variants included (name like "arrow.r.long"). Static storage.
typedef struct { TbStr name; TbStr text; bool emoji; } TbSymbol;
uint32_t tb_symbol_count(void);
TbSymbol tb_symbol(uint32_t index);

// Bibliography: BibLaTeX (yaml false) or hayagriva YAML text, parsed with the crate typst uses. Never NULL; on a
// parse failure the error is non-empty and there are no entries. Strings borrowed until tb_bib_free.
typedef struct TbBib TbBib;
typedef struct { TbStr key; TbStr title; TbStr authors; int32_t year; bool has_year; TbStr kind; } TbBibEntry;
TbBib      *tb_bibliography(TbStr text, bool yaml);
TbStr       tb_bib_error(const TbBib *);
uint32_t    tb_bib_count(const TbBib *);
TbBibEntry  tb_bib_entry(const TbBib *, uint32_t index);
void        tb_bib_free(TbBib *);
#endif
