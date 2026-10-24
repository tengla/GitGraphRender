import Foundation
import Testing
@testable import git_graph

@Suite struct GitRepositoryTests {

    @Test func discoversTopLevelFromASubdirectory() throws {
        let repo = try TestRepo.branchAndMerge()
        try repo.write("nested/dir/file.txt", "x\n")
        let found = try GitRepository.discover(at: repo.url.appendingPathComponent("nested/dir").path)
        #expect(found.topLevel.resolvingSymlinksInPath() == repo.url.resolvingSymlinksInPath())
    }

    @Test func discoverThrowsOutsideARepository() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(throws: GitRepository.GitError.self) {
            try GitRepository.discover(at: dir.path)
        }
    }

    @Test func loadsAllCommitsWithRefs() throws {
        let repo = try TestRepo.branchAndMerge()
        let git = try GitRepository.discover(at: repo.url.path)
        let (commits, total) = try git.loadCommits(maxCount: 100, allBranches: true)

        #expect(total == 4)
        #expect(commits.map(\.subject).sorted() == ["feature work", "init", "main work", "merge feature"])

        let merge = try #require(commits.first)
        #expect(merge.subject == "merge feature")
        #expect(merge.parents.count == 2)
        #expect(merge.refs.contains { $0.name == "v1.0" && $0.kind == .tag })
        #expect(merge.refs.contains { $0.name == "main" })
    }

    /// GraphLayout depends on `--topo-order`: every commit before its parents.
    @Test func emitsChildrenBeforeParents() throws {
        let repo = try TestRepo.branchAndMerge()
        let git = try GitRepository.discover(at: repo.url.path)
        let (commits, _) = try git.loadCommits(maxCount: 100, allBranches: true)

        let position = Dictionary(uniqueKeysWithValues: commits.enumerated().map { ($1.hash, $0) })
        for (index, commit) in commits.enumerated() {
            for parent in commit.parents {
                let parentIndex = try #require(position[parent])
                #expect(parentIndex > index, "\(commit.subject) must come before its parent")
            }
        }
    }

    @Test func maxCountCapsCommitsButReportsTotal() throws {
        let repo = try TestRepo.branchAndMerge()
        let git = try GitRepository.discover(at: repo.url.path)
        let (commits, total) = try git.loadCommits(maxCount: 2, allBranches: true)
        #expect(commits.count == 2)
        #expect(total == 4)
    }

    @Test func diffContainsThePatch() throws {
        let repo = try TestRepo.branchAndMerge()
        let hash = try repo.git("rev-parse", "main~1")   // "main work"
        let diff = try GitRepository.discover(at: repo.url.path).diff(for: hash)
        #expect(diff.contains("diff --git a/README.md b/README.md"))
        #expect(diff.contains("+world"))
    }

    @Test func diffRejectsAnythingButAHash() throws {
        let repo = try TestRepo.branchAndMerge()
        let git = try GitRepository.discover(at: repo.url.path)
        #expect(git.diff(for: "HEAD; rm -rf /") == "Invalid commit hash.")
    }

    /// A patch with non-UTF-8 bytes used to decode to nil and blank the whole diff.
    @Test func diffSurvivesNonUTF8Content() throws {
        let repo = try TestRepo()
        try repo.write("latin1.txt", Data([0x48, 0xE9, 0x0A]))   // "Hé" in Latin-1
        let hash = try repo.commit("latin-1 file")
        let diff = try GitRepository.discover(at: repo.url.path).diff(for: hash)
        #expect(diff.contains("diff --git a/latin1.txt b/latin1.txt"))
    }
}
