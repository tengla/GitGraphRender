import Foundation

/// A single git reference (branch, tag, remote branch, or HEAD) pointing at a commit.
struct Ref: Codable {
    enum Kind: String, Codable {
        case head        // the symbolic HEAD (current checkout)
        case localBranch
        case remoteBranch
        case tag
    }

    let name: String     // display name, e.g. "main", "origin/main", "v1.2.0"
    let kind: Kind
}

/// One commit, with everything the graph and the detail panel need.
///
/// `lane` and `color` are filled in later by `GraphLayout`; `git log` does not
/// provide them. They default to placeholders until layout runs.
struct Commit: Codable {
    let hash: String          // full 40-char SHA
    let shortHash: String     // abbreviated SHA
    let parents: [String]     // full SHAs of parent commits (>1 ⇒ a merge)
    let authorName: String
    let authorEmail: String
    let timestamp: Double     // author date, seconds since epoch
    let subject: String       // first line of the message
    let body: String          // remainder of the message (may be empty)
    var refs: [Ref]           // branches/tags/HEAD pointing here (often empty)

    // Layout-assigned, populated by GraphLayout.
    var lane: Int = 0         // horizontal column this commit sits in
    var color: Int = 0        // palette index for this commit's lane

    /// For each parent, the lane its connecting edge should terminate in.
    /// Parallel to `parents`. Populated by GraphLayout.
    var parentLanes: [Int] = []
}

/// One commit in an author's activity report — a trimmed `Commit` with only the
/// fields the author panel renders. Fetched lazily (repo-wide) on click, separate
/// from the graph's loaded commits, so it isn't limited to HEAD's history.
struct AuthorCommit: Codable {
    let hash: String
    let shortHash: String
    let timestamp: Double
    let subject: String
}

/// The activity report for a single author, computed by one `git log --all`.
/// Spans the whole repo (not just the loaded graph), and excludes merge commits
/// so the numbers reflect authored work rather than PR-merge clicks.
struct AuthorActivity: Codable {
    let name: String           // most-recent display name for this author
    let email: String          // the identity we queried on
    let commits: [AuthorCommit] // newest-first, merges excluded
    let mergeCount: Int        // merge commits authored (shown separately)
}

/// A commit that owns at least one line in a blame. `previousHash`/`previousPath`
/// are git's `previous` field — the commit's parent and the file's path there —
/// i.e. where to blame next to see the file *before* this change. Both are nil
/// when the lines were added by a root commit (nothing further back).
struct BlameCommit: Codable {
    let hash: String
    let shortHash: String
    let author: String
    let authorEmail: String
    let authorTime: Double    // seconds since epoch
    let summary: String       // first line of the message
    let filename: String      // the file's path in this commit (differs after renames)
    let previousHash: String?
    let previousPath: String?
}

/// One line of a blamed file.
struct BlameLine: Codable {
    let hash: String          // commit that last changed this line
    let origLine: Int         // line number in that commit's version of the file
    let text: String
}

/// `git blame` of one file at one commit, fetched lazily on request.
struct BlameResult: Codable {
    let commit: Commit        // the revision blamed (resolved), for the header
    let path: String
    let lines: [BlameLine]    // in file order; line N is lines[N - 1]
    let commits: [String: BlameCommit]
    let truncated: Bool       // true when the file was cut at the line cap
}

/// The full payload handed to the WebView: commits plus a little metadata.
struct GraphData: Codable {
    let commits: [Commit]
    let totalLanes: Int       // width of the widest point, for SVG sizing
    let shownCount: Int       // commits actually included
    let totalCount: Int       // commits in the repo (≥ shownCount when capped)
    let repoName: String      // basename of the repo top-level, for the title
    let truncated: Bool       // true when shownCount < totalCount
}
