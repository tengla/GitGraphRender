import Foundation

/// Assigns each commit a lane (horizontal column) and a color, and records which
/// lane each of its parent edges should descend into. This is what turns a flat
/// list of commits into the familiar branching/merging picture.
///
/// ## The algorithm
///
/// Commits come in newest-first (the order `git log` emits). We sweep top to
/// bottom maintaining a list of *active lanes*. Each active lane holds the SHA of
/// the commit we expect to draw next in that column — i.e. a child has already
/// reserved that column for one of its parents.
///
/// For each commit C:
///  1. Find the leftmost lane reserved for C (a child pointed here). That becomes
///     C's lane. If none exists, C is a brand-new tip: open a fresh lane.
///  2. C's *first* parent inherits C's lane (so a straight line of history stays
///     in one column). Each additional parent (merges) gets the leftmost free
///     lane, opening new columns as needed.
///  3. Any other lanes that were also reserved for C (because C is the merge point
///     of several branches) collapse — those columns close here.
///
/// The result matches what GitKraken / VS Code "Git Graph" draw, and naturally
/// handles octopus merges (3+ parents) and multiple roots.
enum GraphLayout {

    /// Number of distinct colors lanes cycle through (see the palette in CSS/JS).
    static let colorCount = 8

    /// - Returns: the commits with `lane`, `color`, and `parentLanes` filled in,
    ///   plus the total number of lanes used (the widest point), for SVG sizing.
    static func assign(_ input: [Commit]) -> (commits: [Commit], totalLanes: Int) {
        var commits = input

        // Index from SHA → position, so we can tell whether a parent is actually
        // present in the (possibly capped) list we loaded.
        var indexOf: [String: Int] = [:]
        for (i, c) in commits.enumerated() { indexOf[c.hash] = i }

        // activeLanes[lane] == the SHA expected next in that column, or nil if free.
        var activeLanes: [String?] = []
        // Stable color per lane, chosen when the lane is first opened.
        var laneColor: [Int] = []
        var nextColor = 0
        var maxLanes = 0

        /// Opens a lane for `sha`, reusing the leftmost free slot if any.
        func openLane(for sha: String) -> Int {
            if let free = activeLanes.firstIndex(where: { $0 == nil }) {
                activeLanes[free] = sha
                laneColor[free] = nextColor % colorCount
                nextColor += 1
                return free
            }
            activeLanes.append(sha)
            laneColor.append(nextColor % colorCount)
            nextColor += 1
            return activeLanes.count - 1
        }

        for i in commits.indices {
            let commit = commits[i]

            // 1. Which lane is this commit drawn in? The leftmost lane reserved for it.
            let myLane: Int
            if let reserved = activeLanes.firstIndex(where: { $0 == commit.hash }) {
                myLane = reserved
            } else {
                // No child reserved a column → a new branch tip.
                myLane = openLane(for: commit.hash)
            }

            commits[i].lane = myLane
            commits[i].color = laneColor[myLane]

            // 2. Close every *other* lane that was also waiting for this commit
            //    (branches merging into it converge here).
            for lane in activeLanes.indices where lane != myLane && activeLanes[lane] == commit.hash {
                activeLanes[lane] = nil
            }

            // 3. Route the parents.
            var parentLanes: [Int] = []
            if commit.parents.isEmpty {
                // Root commit: its lane closes after this row.
                activeLanes[myLane] = nil
            } else {
                for (pIndex, parent) in commit.parents.enumerated() {
                    // A parent not in our loaded slice (history was capped, or it's
                    // a graft) still gets an edge stub that simply ends; we route it
                    // into a lane so the line is drawn, then let that lane close.
                    let hasParent = indexOf[parent] != nil

                    if pIndex == 0 {
                        // First parent keeps this commit's lane (straight history).
                        activeLanes[myLane] = hasParent ? parent : nil
                        parentLanes.append(myLane)
                    } else {
                        // Additional parents (merge): does some lane already expect
                        // this parent? If so, merge into it; else open a new lane.
                        if let existing = activeLanes.firstIndex(where: { $0 == parent }) {
                            parentLanes.append(existing)
                        } else if hasParent {
                            let newLane = openLane(for: parent)
                            parentLanes.append(newLane)
                        } else {
                            // Parent outside the slice: a short stub in a temp lane.
                            let stub = openLane(for: parent)
                            activeLanes[stub] = nil
                            parentLanes.append(stub)
                        }
                    }
                }
            }
            commits[i].parentLanes = parentLanes

            maxLanes = max(maxLanes, activeLanes.count)
        }

        // Post-pass: rewrite each parent edge to terminate at the parent's *final*
        // lane. During the forward sweep we route an edge into whatever lane was
        // reserved for the parent, but when several branches converge on one commit
        // that commit is ultimately drawn in only the leftmost of those lanes. Any
        // edge aimed at a now-collapsed lane would miss the node; pointing it at the
        // parent's real lane keeps every line connected to its endpoint.
        for i in commits.indices {
            for pi in commits[i].parentLanes.indices {
                let parentHash = commits[i].parents[pi]
                if let pIndex = indexOf[parentHash] {
                    commits[i].parentLanes[pi] = commits[pIndex].lane
                }
            }
        }

        return (commits, max(maxLanes, 1))
    }
}
