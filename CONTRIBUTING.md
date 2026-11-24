# Contributing to Typo

Thank you for helping. Typo is a native Typst editor for macOS, built and maintained by one person, so small, focused contributions work best.

## Before you start

- **Bugs:** open an issue with the bug form first. Search the existing issues before you do.
- **Features:** open an issue with the feature form and describe the problem, not only the solution. Wait for a reply before you write a large change, so your work isn't wasted on something that won't be merged.
- **Small fixes** (typos, an obvious bug with a one-line fix, documentation) can go straight to a pull request.
- **Security problems:** don't open a public issue. Use "Report a vulnerability" on the repository's Security tab.

## License of your contribution

Typo is source-available, not open source. Read [LICENSE](LICENSE) before you contribute. By sending a pull request you allow the copyright holder to use, change and distribute your contribution, including under other license terms (section 3 of the license). Only send code you wrote yourself or are allowed to give under these terms.

## Building

You need macOS 27, Xcode 27, a Rust toolchain (`rustup`) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
./build.sh --debug --open
```

The first build compiles the Typst engine in `bridge/`, which takes a few minutes. Later builds skip it unless its Rust code changed. To work in Xcode, run `./build.sh` once and open `Typo.xcodeproj`. The project file is generated from `project.yml`: change `project.yml`, never the `.xcodeproj`, and run `xcodegen generate` after you add or remove files.

## Where things are

- `App/`: the app target (SwiftUI and AppKit views, menus, settings).
- `Packages/Typo/`: the Swift package with the editor logic, split into modules:
  - `TypstEngine`: the Swift side of the Rust bridge.
  - `TypoKit`: editing, projects, completion, formatting, Git, export.
  - `TypoAssistant`, `TypoACP`, `TypoMCP`: the assistant, agents and the MCP server.
- `bridge/`: the Typst engine as a Rust library.
- `Workflows/`: the built-in assistant workflows (`/check`, `/submit`, …) as Markdown.
- `docs/`: the website.

Put logic that can be tested without the UI into `Packages/Typo`, and keep `App/` for views and wiring.

## Tests

```bash
cd Packages/Typo && swift test
```

Add a test for every bug fix and for new logic in the package. Tests check what the code does for its users, not how it is built inside. UI changes need a screenshot or a short screen recording in the pull request instead.

## Code style

- Swift 6 with strict concurrency. The build must have no new warnings.
- Follow the code around your change: naming, structure, the existing helpers.
- Keep changes small. A pull request does one thing. Refactoring goes in its own pull request.
- Comments explain why, not what. Leave out comments the code already says.
- No new dependencies without asking in an issue first.
- Accessibility is part of a feature: label controls for VoiceOver, support the keyboard and respect Reduce Motion.

## Pull requests

1. Fork the repository and create a branch from `main`.
2. Make your change, with tests.
3. Run `./build.sh --test` and make sure it passes.
4. Open the pull request and fill in the template. Link the issue it fixes (`Fixes #123`).

Commit messages: one short line in the imperative ("Fix the outline when a heading is folded"), then, if needed, a blank line and a few lines on why.

Expect a reply within a few hours. A pull request may be closed if it doesn't fit the direction of the project; that's no judgment of your work.
