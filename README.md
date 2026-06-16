# git-graph

A native macOS command-line tool that renders a git repository's history as a
beautiful, interactive commit graph in a window — colored branch lanes, merge
curves, ref labels, and click-to-inspect diffs.

It's the sibling of [MarkdownRender](../MarkdownRender): same idea — type one
command, get a polished native window — but for git history instead of Markdown.

## Features

- **Visual commit graph** — colored nodes connected by curved branch/merge lanes,
  like the VS Code "Git Graph" extension or GitKraken
- **Branch, tag & HEAD labels** — shown as pills right on the graph
- **Click any commit** — a side panel slides in with the full message, author,
  date, and the commit's diff (`git show --stat --patch`)
- **Hover tooltips** — quick subject + hash + author
- **Filter/search** — ⌘F to filter commits by message, author, or hash
- **Dark/light mode** — follows system appearance or manual override
- **Live reload** — ⌘R, or `--watch` to auto-refresh when you commit/checkout
- **Fully offline** — the graph is drawn with hand-written SVG; no network needed

## Requirements

- **macOS 13.0 (Ventura) or later** — the app uses AppKit and WebKit
- **Swift 5.9+ toolchain** — the Xcode command-line tools provide it
  (`xcode-select --install`)
- **`git` on your `PATH`** — git-graph shells out to it at runtime; the
  command-line tools include it

No network connection is needed: the graph is drawn entirely on-device.

## Building

The project is a Swift package — there is no Xcode project to open.

```bash
git clone https://github.com/tengla/GitGraphRender.git
cd GitGraphRender

# Debug build
swift build

# Optimized release build → .build/release/git-graph
swift build -c release
```

Run it without installing:

```bash
swift run git-graph                 # the repo in the current directory
swift run git-graph /path/to/repo   # any other repository
```

If you have [Task](https://taskfile.dev) installed, the included `Taskfile.yml`
wraps these: `task build`, `task build:release`, `task run`, `task size`, and
`task --list` to see them all.

## Installation

Build the release binary (see [Building](#building)) and copy it onto your `PATH`:

```bash
swift build -c release
mkdir -p ~/bin
cp .build/release/git-graph ~/bin/
# ensure ~/bin is on your PATH
```

Or let the Taskfile do it: `task install` (installs to `~/bin`).

## Usage

```bash
# Show the graph for the repo in the current directory
git-graph

# Point it at another repository
git-graph /path/to/repo

# Show all branches and remotes, not just HEAD's history
git-graph --all

# Limit how many commits are loaded (newest first; default 500)
git-graph --max 200

# Force dark or light theme
git-graph --theme dark
git-graph --theme light

# Watch the repo and reload automatically on new commits/checkouts
git-graph --watch

# Show help
git-graph --help
```

## How it works

`git-graph` shells out to the system `git` once (`git log --topo-order` with a
machine-readable format), assigns each commit a lane and color with a standard
branch-tracking layout algorithm, serializes the result to JSON, and renders it
as SVG inside a `WKWebView`. Clicking a commit lazily fetches its diff via
`git show` so the initial load stays fast even on large repositories.

## Project Structure

```
GitGraphRender/
├── Package.swift                      # Swift Package Manager manifest
└── Sources/git-graph/
    ├── main.swift                     # CLI entry point (ArgumentParser)
    ├── App/
    │   └── AppDelegate.swift          # Window, WebView, menu, diff bridge, watch
    ├── Git/
    │   ├── GitModels.swift            # Commit / Ref / GraphData (Codable)
    │   └── GitRepository.swift        # Runs git, parses the log, fetches diffs
    └── Rendering/
        ├── GraphLayout.swift          # Lane/color assignment (the graph algorithm)
        └── HTMLGenerator.swift        # HTML/CSS/JS that draws the SVG graph
```

## Dependencies

- [swift-argument-parser](https://github.com/apple/swift-argument-parser) — CLI parsing

That's the only third-party dependency; everything else uses AppKit/WebKit and the
system `git`.

## License

MIT
