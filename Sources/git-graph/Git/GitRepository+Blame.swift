import Foundation

/// `git blame` for the blame view, plus the file list its path field suggests from.
extension GitRepository {

    /// `git blame` of `path` at `revision` (anything `commit(for:)` accepts).
    /// Long files are cut at `maxLines` so a huge generated file can't freeze
    /// the WebView. Throws `unknownRevision`, or `commandFailed` with git's
    /// message (e.g. the path doesn't exist at that revision).
    func blame(path: String, revision: String, maxLines: Int = 20_000) throws -> BlameResult {
        // `git blame` misparses `--end-of-options`, so resolve the revision first
        // (that lookup is guarded) and pass blame only the 40-hex SHA it returns.
        // The path goes after `--`, so it can't be read as an option either.
        let commit = try commit(for: revision)
        let path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { throw GitError.commandFailed("No file given to blame.") }
        let raw: String
        do {
            raw = try Self.run(["-C", topLevel.path, "blame", "--porcelain", commit.hash, "--", path],
                               workingDirectory: topLevel)
        } catch GitError.commandFailed(let message) {
            throw GitError.commandFailed(message.replacingOccurrences(of: "fatal: ", with: ""))
        }
        let (lines, commits) = Self.parseBlame(raw)
        return BlameResult(commit: commit, path: path, lines: Array(lines.prefix(maxLines)),
                           commits: commits, truncated: lines.count > maxLines)
    }

    /// Parses `git blame --porcelain`. Each line group starts with
    /// "<sha> <orig-line> <final-line> [<count>]"; the first time a commit
    /// appears, header fields (author, summary, previous, filename, …) follow.
    /// Every content line is prefixed with a tab.
    static func parseBlame(_ raw: String) -> (lines: [BlameLine], commits: [String: BlameCommit]) {
        var lines: [BlameLine] = []
        var commits: [String: BlameCommit] = [:]
        var hash: String?
        var origLine = 0
        var fields: [String: String] = [:]

        for row in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            if row.hasPrefix("\t") {
                guard let current = hash else { continue }
                if commits[current] == nil {
                    let previous = fields["previous"].map { $0.split(separator: " ", maxSplits: 1) }
                    commits[current] = BlameCommit(
                        hash: current,
                        shortHash: String(current.prefix(7)),
                        author: fields["author"] ?? "",
                        authorEmail: (fields["author-mail"] ?? "")
                            .trimmingCharacters(in: CharacterSet(charactersIn: "<>")),
                        authorTime: Double(fields["author-time"] ?? "") ?? 0,
                        summary: fields["summary"] ?? "",
                        filename: fields["filename"] ?? "",
                        previousHash: previous.flatMap { $0.first.map(String.init) },
                        previousPath: previous.flatMap { $0.count > 1 ? String($0[1]) : nil })
                }
                lines.append(BlameLine(hash: current, origLine: origLine, text: String(row.dropFirst())))
                hash = nil
                fields = [:]
            } else if hash == nil {
                // Group header: "<sha> <orig-line> <final-line> [<count>]".
                let parts = row.split(separator: " ")
                guard parts.count >= 3 else { continue }
                hash = String(parts[0])
                origLine = Int(parts[1]) ?? 0
            } else {
                let pair = row.split(separator: " ", maxSplits: 1)
                if let key = pair.first {
                    fields[String(key)] = pair.count > 1 ? String(pair[1]) : ""
                }
            }
        }
        return (lines, commits)
    }

    /// Paths of every file in `revision`'s tree, for the blame prompt's
    /// suggestions. Capped, since a datalist with 100k entries helps no one.
    func files(at revision: String, limit: Int = 20_000) throws -> [String] {
        let revision = revision.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !revision.isEmpty, !revision.hasPrefix("-") else { throw GitError.unknownRevision(revision) }
        let out = try Self.run(["-C", topLevel.path, "ls-tree", "-r", "--name-only", "-z",
                                "--end-of-options", revision + "^{commit}"],
                               workingDirectory: topLevel)
        return Array(out.split(separator: "\u{0}").prefix(limit).map(String.init))
    }
}
