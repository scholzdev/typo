---
name: packages
description: Use Typst Universe packages and templates (imports, versions, typst.toml). Use when the user wants a package, a template, or an import fails.
---

# Packages

- Import with a full version: `#import "@preview/name:1.2.3": item`. Never leave out the version or make one up; check `typst_docs` or ask the user which version the project uses.
- Prefer an import that names what you use over `*`.
- Typo downloads packages on first use and keeps a local cache, so a new import may need a moment and network once. If a package can't be fetched, tell the user; don't replace it with hand-written code without asking.
- `typst.toml` describes a package or template project (name, version, entrypoint). Leave it unchanged unless the user asks.
- Local packages live under `@local/name:version`.
- After adding an import, `get_diagnostics` and check the package's API with its documentation before calling functions.
