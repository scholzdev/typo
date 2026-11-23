# Judge rubric (runners do not see this)

1. Edit integrity: no edit lost, duplicated or reordered between text view, engine and disk; UTF-16 contract consistent end to end; works for several open files; results computed against an older text revision never mark or jump to the wrong text.
2. Responsiveness: main thread never waits on compile/render/IO; compiles coalesce; only visible changed pages re-render; bounded image memory.
3. Interface depth: the app sees a small, typed API; JSON/C types never leak past the bridge wrapper; the C ABI is minimal and handle-based.
4. Single owner per piece of state (text, diagnostics, page snapshots, security-scoped access); no hand-synced lists.
5. Portability: the core builds for iOS 27 unchanged; sandbox access handled in one place; the iPad app later needs only new views.
6. Smallness: the smallest design that delivers the scope above; no speculative layers.
