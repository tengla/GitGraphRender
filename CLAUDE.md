# CLAUDE.md

This file provides guidance for Claude Code when working on this project.

## Project Overview

git-graph is a native macOS CLI tool that opens a window rendering a git
repository's commit history as a beautiful, interactive graph (colored branch
lanes, merge curves, ref pills, click-to-inspect diffs). It uses Swift Package
Manager (not an Xcode project) and is modeled on the sibling project
MarkdownRender — same AppKit-window-hosting-a-WKWebView approach.

## Build Commands

```bash
# Debug build
swift build

# Release build
swift build -c release

# Run against the current directory's repo
swift run git-graph

# Run against another repo, with options
swift run git-graph --all --theme dark /path/to/repo
```

The release binary is at `.build/release/git-graph`.

## Architecture

```
Sources/git-graph/
├── main.swift                  # CLI entry, argument parsing with ArgumentParser
├── App/
│   └── AppDelegate.swift       # NSApplication delegate, window, WebView, diff bridge, watch
├── Git/
│   ├── GitModels.swift         # Commit / Ref / GraphData — Codable, serialized to JSON
│   └── GitRepository.swift     # Process-based git runner + log parser + diff fetch
└── Rendering/
    ├── GraphLayout.swift       # Lane/color assignment algorithm
    └── HTMLGenerator.swift     # HTML template, CSS, and the SVG-drawing JS
```

### Data flow

1. `main.swift` resolves the repo (`GitRepository.discover`) and launches the app.
2. `AppDelegate.loadGraph()` calls `GitRepository.loadCommits()` (one `git log`),
   runs `GraphLayout.assign()` to fill in lanes/colors/parent-edges, encodes the
   `GraphData` to JSON, and hands it to `HTMLGenerator.generateHTML()`.
3. JS in the WebView reads the embedded JSON and draws the SVG graph + commit rows.
4. Clicking a commit posts its hash to Swift via a `WKScriptMessageHandler`
   (`commit` handler); `AppDelegate` runs `git show` and calls `window.renderDiff`.

### Key Design Decisions

1. **No Xcode project** — SPM only. Open `Package.swift` in Xcode for IDE features.
2. **System `git`, not libgit2** — already installed, always current, handles every
   repo quirk. One `git log` process keeps load fast.
3. **`--topo-order` is mandatory** — `GraphLayout` requires each commit to be emitted
   before any of its parents. Plain date order breaks this when timestamps tie or
   clocks are skewed, corrupting merge edges. Do not remove it.
4. **Hand-drawn SVG, no CDN** — git data is small and we control the layout, so the
   tool works fully offline (unlike MarkdownRender, which loads diagram libs from CDN).
5. **Lazy diffs** — the embedded JSON has no patch text; diffs are fetched on click
   via `git show`, keeping initial load fast on large repos.
6. **Theme support** — CSS uses `prefers-color-scheme`; `--theme` sets the
   `NSWindow.appearance` to override, same as MarkdownRender.

## Code Patterns

### The lane layout algorithm (GraphLayout.swift)

Sweeps commits newest→oldest tracking "active lanes" (columns reserved by a child
for one of its parents). A commit takes the leftmost lane reserved for it; its first
parent inherits that lane (straight history), additional parents open/merge lanes.
A final post-pass rewrites every parent edge to the parent's *real* assigned lane so
edges always land on their node even when branches converge. See the file's doc
comment for the full description.

### Adding a field to the graph data

1. Add it to the relevant struct in `GitModels.swift` (keep it `Codable`).
2. Populate it in `GitRepository.parseLog` (extend the `--pretty=format:` string and
   the field indices) or in `GraphLayout`.
3. Read it from the `GRAPH_DATA` object in `HTMLGenerator.generateJS()`.

### Changing the look

Edit `HTMLGenerator.generateCSS()`. Theming uses CSS variables
(`--bg-color`, `--text-color`, `--lane-0`…`--lane-7`, …) with dark-mode overrides
under `@media (prefers-color-scheme: dark)`. Drawing constants (lane width, row
height, dot radius) live at the top of `generateJS()`.

## Testing / verifying changes

The graph rendering can be verified headlessly without opening a window:

1. Build a repo with branches and a merge (so lanes/merges are exercised), e.g.
   `git init`, a couple of commits, a feature branch, a `--no-ff` merge, a tag.
2. Render its HTML via the real `HTMLGenerator` and open it in headless Chrome to
   execute the JS and screenshot it:
   ```bash
   "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
     --headless --disable-gpu --screenshot=out.png file:///path/to/rendered.html
   ```
3. Confirm: every commit has a `.commit-row`, each has a `<circle>`, parent links
   have a `<path>`, and merge/branch edges curve into the correct lanes.

Then launch the real app: `swift run git-graph --all /path/to/repo`.

## Common Tasks

### Update minimum macOS version

Edit `Package.swift`: `platforms: [.macOS(.v13)]`.

### Add a new dependency

Edit `Package.swift` and add to both `dependencies` and the target's `dependencies`.

### Add a new CLI option

Add an `@Option`/`@Flag` in `main.swift`'s `GitGraph` command, thread it through to
`AppDelegate`, and use it in `loadGraph()` or `GitRepository`.
