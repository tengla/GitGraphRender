import AppKit
import ArgumentParser

struct GitGraph: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "git-graph",
        abstract: "Render a git repository's history as a beautiful, interactive graph in a native macOS window."
    )

    @Argument(help: "Path to a git repository. Defaults to the current directory.")
    var path: String = "."

    @Option(name: .shortAndLong, help: "Theme: 'auto', 'light', or 'dark'.")
    var theme: String = "auto"

    @Option(name: .shortAndLong, help: "Maximum number of commits to show (newest first).")
    var max: Int = 500

    @Flag(name: .shortAndLong, help: "Include all branches and remotes, not just HEAD's history.")
    var all: Bool = false

    @Flag(name: .shortAndLong, help: "Watch the repo and reload automatically on new commits/checkouts.")
    var watch: Bool = false

    mutating func run() throws {
        guard ["auto", "light", "dark"].contains(theme) else {
            throw ValidationError("Theme must be 'auto', 'light', or 'dark'.")
        }
        guard max > 0 else {
            throw ValidationError("--max must be a positive number.")
        }

        // Resolve the repository up front so we can report "not a git repo" as a
        // clean CLI error rather than opening a window just to show the failure.
        let repo: GitRepository
        do {
            repo = try GitRepository.discover(at: path)
        } catch let error as GitRepository.GitError {
            throw ValidationError(error.errorDescription ?? "Could not open repository.")
        }

        let app = NSApplication.shared
        let delegate = AppDelegate(repo: repo, theme: theme, maxCount: max, allBranches: all, watchEnabled: watch)
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

GitGraph.main()
