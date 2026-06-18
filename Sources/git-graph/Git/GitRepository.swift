import Foundation

/// Reads commit history out of a git repository by shelling out to the `git` CLI.
///
/// We use the system `git` (rather than linking libgit2) for the same reason
/// MarkdownRender leans on the system markdown stack: it's already installed,
/// always up to date, and handles every repo quirk correctly. History is small,
/// so a single `git log` process is plenty fast.
struct GitRepository {

    enum GitError: LocalizedError {
        case notARepository(String)
        case gitNotFound
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .notARepository(let path):
                return "Not a git repository: \(path)"
            case .gitNotFound:
                return "The `git` command was not found. Install the Xcode command-line tools or Git."
            case .commandFailed(let message):
                return message
            }
        }
    }

    /// Absolute path to the repository's top level (the directory containing `.git`).
    let topLevel: URL

    var repoName: String { topLevel.lastPathComponent }

    // MARK: - Discovery

    /// Resolves the repository that `path` lives in. Throws `notARepository` if
    /// `path` is not inside a git work tree.
    static func discover(at path: String) throws -> GitRepository {
        let resolved = URL(fileURLWithPath: path).standardizedFileURL
        let output: String
        do {
            output = try run(["-C", resolved.path, "rev-parse", "--show-toplevel"],
                             workingDirectory: resolved)
        } catch GitError.commandFailed {
            throw GitError.notARepository(resolved.path)
        }
        let topLevel = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !topLevel.isEmpty else { throw GitError.notARepository(resolved.path) }
        return GitRepository(topLevel: URL(fileURLWithPath: topLevel))
    }

    // MARK: - Loading the graph

    /// Field/record separators. `git log` lets us emit raw control characters via
    /// `%x1f`/`%x1e`, which never collide with commit text, so parsing is trivial
    /// and robust against newlines, tabs, quotes, etc. in commit messages.
    private static let fieldSep = "\u{1f}"   // between fields of one record
    private static let recordSep = "\u{1e}"  // between records (commits)

    /// Runs one `git log` and parses it into commits (no lane info yet).
    ///
    /// - Parameters:
    ///   - maxCount: cap on how many commits to read (newest first).
    ///   - allBranches: when true, include every ref (`--all`); otherwise just
    ///     what's reachable from HEAD.
    func loadCommits(maxCount: Int, allBranches: Bool) throws -> (commits: [Commit], totalCount: Int) {
        // %H hash, %h short, %P parents, %an author, %ae email, %at unix time,
        // %s subject, %b body, %D ref names. Order matters — parsing relies on it.
        let format = [
            "%H", "%h", "%P", "%an", "%ae", "%at", "%s", "%b", "%D"
        ].joined(separator: Self.fieldSep) + Self.recordSep

        // --topo-order is essential, not cosmetic: the lane algorithm in
        // GraphLayout requires every commit to be emitted before any of its
        // parents. Plain date order violates that when commits share timestamps
        // (or when clocks are skewed across machines), which corrupts merge edges.
        var args = ["-C", topLevel.path, "log",
                    "--pretty=format:\(format)",
                    "--topo-order",
                    "-z",                       // NUL-terminate records too (belt and suspenders)
                    "--max-count=\(maxCount)"]
        if allBranches {
            args.append("--all")
        }

        let raw: String
        do {
            raw = try Self.run(args, workingDirectory: topLevel)
        } catch GitError.commandFailed(let msg) {
            // An empty repo (no commits) makes `git log` fail with a known message.
            if msg.contains("does not have any commits")
                || msg.contains("bad default revision")
                || msg.lowercased().contains("ambiguous argument 'head'") {
                return ([], 0)
            }
            throw GitError.commandFailed(msg)
        }

        let commits = Self.parseLog(raw)
        let total = (try? countCommits(allBranches: allBranches)) ?? commits.count
        return (commits, max(total, commits.count))
    }

    /// Total number of commits, so the UI can say "showing 500 of 4,213".
    private func countCommits(allBranches: Bool) throws -> Int {
        var args = ["-C", topLevel.path, "rev-list", "--count"]
        args.append(allBranches ? "--all" : "HEAD")
        let out = try Self.run(args, workingDirectory: topLevel)
        return Int(out.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    private static func parseLog(_ raw: String) -> [Commit] {
        // Records are separated by recordSep; with `-z` git also appends a NUL.
        let cleaned = raw.replacingOccurrences(of: "\u{00}", with: "")
        let records = cleaned.components(separatedBy: recordSep)

        var commits: [Commit] = []
        commits.reserveCapacity(records.count)

        for record in records {
            let trimmed = record.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            let fields = record.components(separatedBy: fieldSep)
            guard fields.count >= 9 else { continue }

            let hash = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !hash.isEmpty else { continue }

            let parents = fields[2]
                .split(separator: " ")
                .map { String($0) }
                .filter { !$0.isEmpty }

            let commit = Commit(
                hash: hash,
                shortHash: fields[1].trimmingCharacters(in: .whitespacesAndNewlines),
                parents: parents,
                authorName: fields[3],
                authorEmail: fields[4],
                timestamp: Double(fields[5].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0,
                subject: fields[6],
                body: fields[7].trimmingCharacters(in: .whitespacesAndNewlines),
                refs: parseRefs(fields[8])
            )
            commits.append(commit)
        }
        return commits
    }

    /// Parses the `%D` ref string, e.g. "HEAD -> main, origin/main, tag: v1.0".
    private static func parseRefs(_ raw: String) -> [Ref] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var refs: [Ref] = []
        for piece in trimmed.components(separatedBy: ",") {
            var name = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { continue }

            // "HEAD -> main" means HEAD currently points at branch main.
            if name.hasPrefix("HEAD -> ") {
                refs.append(Ref(name: "HEAD", kind: .head))
                name = String(name.dropFirst("HEAD -> ".count))
                refs.append(Ref(name: name, kind: .localBranch))
            } else if name == "HEAD" {
                refs.append(Ref(name: "HEAD", kind: .head))     // detached HEAD
            } else if name.hasPrefix("tag: ") {
                refs.append(Ref(name: String(name.dropFirst("tag: ".count)), kind: .tag))
            } else if name.hasPrefix("origin/") || name.contains("/") {
                refs.append(Ref(name: name, kind: .remoteBranch))
            } else {
                refs.append(Ref(name: name, kind: .localBranch))
            }
        }
        return refs
    }

    // MARK: - Lazy diff for the detail panel

    /// Returns `git show --stat --patch <hash>` for the detail panel. Patch output
    /// is capped so a giant commit doesn't freeze the WebView; the cap is noted.
    func diff(for hash: String, maxBytes: Int = 200_000) -> String {
        // Validate the hash so we never interpolate arbitrary strings into args.
        guard hash.range(of: "^[0-9a-fA-F]{4,40}$", options: .regularExpression) != nil else {
            return "Invalid commit hash."
        }
        let args = ["-C", topLevel.path, "show",
                    "--stat", "--patch",
                    "--no-color",
                    "--format=fuller",
                    hash]
        guard let output = try? Self.run(args, workingDirectory: topLevel) else {
            return "Unable to load diff for \(hash)."
        }
        if output.utf8.count > maxBytes {
            let prefix = String(output.prefix(maxBytes / 2))
            return prefix + "\n\n… diff truncated (commit is large) …\n"
        }
        return output
    }

    // MARK: - Lazy author activity for the author panel

    /// Builds an activity report for one author, fetched on click.
    ///
    /// Scoped to the time window of the commits currently loaded in the graph
    /// (`since`/`until`, Unix seconds): the panel answers "what has this author
    /// done within the range I'm looking at", not their entire repo history. Pass
    /// `nil` bounds to span all of time.
    ///
    /// Within that window it queries `--all` so it surfaces the author's *real*
    /// commits on feature branches — not just the merge commits that land on the
    /// checked-out branch. Merges are excluded from the commit list and counted
    /// separately, since in a PR workflow the merge author is whoever clicked
    /// "merge", not who did the work.
    func authorActivity(email: String, since: Double? = nil, until: Double? = nil,
                        maxCount: Int = 2000) -> AuthorActivity? {
        // The email is user-controlled and goes into an --author arg, so guard it:
        // require a basic shape (one "@", no whitespace). The no-whitespace rule
        // also blocks argument injection via newlines. We do NOT blocklist regex
        // metacharacters — legal local-parts contain them (notably "+" in GitHub
        // noreply addresses, and "." everywhere). The fixed-string match below
        // (-F) makes those characters literal, so no escaping is needed.
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.range(of: "^[^\\s@]+@[^\\s@]+$", options: .regularExpression) != nil
        else { return nil }

        let format = ["%H", "%h", "%at", "%an", "%s"].joined(separator: Self.fieldSep) + Self.recordSep

        // `git --author` matches against the whole "Name <email>" ident string.
        // We match it as a *fixed string* (`-F`) rather than a regex: git's regex
        // dialect is POSIX, not PCRE, so backslash-escaping metacharacters (the
        // way NSRegularExpression does) silently fails to match — emails with "+"
        // or "." (e.g. GitHub noreply addresses) would find nothing.
        //
        // Wrapping the email in angle brackets — "<email>" — gives exact-field
        // precision even as a substring: the leading "<" anchors the start of the
        // email field and the trailing ">" anchors its end, so querying "a@b.com"
        // matches neither "xa@b.com" nor "a@b.com.evil".
        // --all spans every ref; --no-merges drops merge commits.
        let authorArg = "--author=<\(trimmed)>"
        var logArgs = ["-C", topLevel.path, "log",
                       "--all", "--no-merges", "-F",
                       "--pretty=format:\(format)",
                       "-z",
                       "--max-count=\(maxCount)"]
        logArgs += Self.dateRangeArgs(since: since, until: until)
        logArgs.append(authorArg)

        guard let raw = try? Self.run(logArgs, workingDirectory: topLevel) else { return nil }

        let cleaned = raw.replacingOccurrences(of: "\u{00}", with: "")
        var commits: [AuthorCommit] = []
        var displayName = ""
        for record in cleaned.components(separatedBy: Self.recordSep) {
            if record.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            let f = record.components(separatedBy: Self.fieldSep)
            guard f.count >= 5 else { continue }
            let hash = f[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !hash.isEmpty else { continue }
            if displayName.isEmpty { displayName = f[3] }   // newest commit's name
            commits.append(AuthorCommit(
                hash: hash,
                shortHash: f[1].trimmingCharacters(in: .whitespacesAndNewlines),
                timestamp: Double(f[2].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0,
                subject: f[4]
            ))
        }

        // Separate count of merge commits this author landed, within the same
        // window (for context — "you landed N PRs in this range").
        var mergeArgs = ["-C", topLevel.path, "rev-list", "--all", "--merges",
                         "-F", "--count"]
        mergeArgs += Self.dateRangeArgs(since: since, until: until)
        mergeArgs.append(authorArg)
        let mergeCount = (try? Self.run(mergeArgs, workingDirectory: topLevel))
            .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 0

        return AuthorActivity(
            name: displayName.isEmpty ? trimmed : displayName,
            email: trimmed,
            commits: commits,
            mergeCount: mergeCount
        )
    }

    /// Builds `--since`/`--until` args from optional Unix-second bounds.
    ///
    /// We pass epoch seconds with an explicit format so git interprets them as
    /// absolute instants (not relative dates). `--until` is inclusive; we nudge it
    /// up by one second so a commit exactly at the newest loaded timestamp isn't
    /// dropped by boundary rounding.
    private static func dateRangeArgs(since: Double?, until: Double?) -> [String] {
        var args: [String] = []
        if let since, since > 0 {
            args.append("--since=\(Int(since.rounded(.down))) +0000")
        }
        if let until, until > 0 {
            args.append("--until=\(Int(until.rounded(.up)) + 1) +0000")
        }
        return args
    }

    // MARK: - Process plumbing

    @discardableResult
    private static func run(_ arguments: [String], workingDirectory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = workingDirectory

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw GitError.gitNotFound
        }

        // Read both pipes before waiting to avoid deadlock on large output.
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "git exited with status \(process.terminationStatus)"
            throw GitError.commandFailed(message)
        }

        return String(data: outData, encoding: .utf8) ?? ""
    }
}
