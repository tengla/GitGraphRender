import Testing
@testable import git_graph

@Suite struct GraphLayoutTests {

    private func commit(_ hash: String, _ parents: [String] = []) -> Commit {
        Commit(hash: hash, shortHash: hash, parents: parents, authorName: "A",
               authorEmail: "a@example.com", timestamp: 0, subject: hash, body: "", refs: [])
    }

    @Test func linearHistoryStaysInOneLane() {
        let (commits, lanes) = GraphLayout.assign([
            commit("c", ["b"]),
            commit("b", ["a"]),
            commit("a")
        ])
        #expect(lanes == 1)
        #expect(commits.allSatisfy { $0.lane == 0 })
        #expect(commits[0].parentLanes == [0])
    }

    @Test func branchAndMergeUsesTwoLanes() {
        // m merges f into main; both branches fork from root.
        let (commits, lanes) = GraphLayout.assign([
            commit("m", ["main", "f"]),
            commit("main", ["root"]),
            commit("f", ["root"]),
            commit("root")
        ])
        let byHash = Dictionary(uniqueKeysWithValues: commits.map { ($0.hash, $0) })

        #expect(lanes == 2)
        #expect(byHash["m"]?.lane == 0)
        #expect(byHash["main"]?.lane == 0)
        #expect(byHash["f"]?.lane == 1)
        #expect(byHash["root"]?.lane == 0)
        // Each edge lands on its parent's real lane.
        #expect(byHash["m"]?.parentLanes == [0, 1])
        #expect(byHash["f"]?.parentLanes == [0])
        #expect(byHash["main"]?.color != byHash["f"]?.color)
    }
}
