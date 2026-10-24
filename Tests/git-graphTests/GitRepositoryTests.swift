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

    /// `git show <rev>` lookups: anything git can resolve, to the commit it names.
    @Test(arguments: [
        ("feature", "feature work"),
        ("main~1", "main work"),
        ("main^2", "feature work"),
        ("v1.0", "merge feature"),
        ("HEAD", "merge feature")
    ])
    func resolvesRevisions(revision: String, subject: String) throws {
        let repo = try TestRepo.branchAndMerge()
        let commit = try GitRepository.discover(at: repo.url.path).commit(for: revision)
        #expect(commit.subject == subject)
    }

    @Test func resolvesShortHashes() throws {
        let repo = try TestRepo.branchAndMerge()
        let full = try repo.git("rev-parse", "feature")
        let commit = try GitRepository.discover(at: repo.url.path).commit(for: String(full.prefix(7)))
        #expect(commit.hash == full)
        #expect(commit.parents.count == 1)
    }

    @Test(arguments: ["no-such-branch", "", "--output=/tmp/pwned", "HEAD~99"])
    func rejectsUnknownRevisions(revision: String) throws {
        let repo = try TestRepo.branchAndMerge()
        let git = try GitRepository.discover(at: repo.url.path)
        #expect(throws: GitRepository.GitError.self) { try git.commit(for: revision) }
    }

    @Test func blameAttributesEachLineAndLinksToThePriorVersion() throws {
        let repo = try TestRepo.branchAndMerge()
        let initHash = try repo.git("rev-parse", "main~2")
        let blame = try GitRepository.discover(at: repo.url.path).blame(path: "README.md", revision: "HEAD")

        #expect(blame.lines.map(\.text) == ["hello", "world"])
        let hello = try #require(blame.commits[blame.lines[0].hash])
        let world = try #require(blame.commits[blame.lines[1].hash])
        #expect(hello.summary == "init")
        #expect(world.summary == "main work")
        #expect(world.author == "Test Author")
        #expect(world.authorEmail == "author@example.com")
        // "Before this change" for main work is init; init has nothing before it.
        #expect(world.previousHash == initHash)
        #expect(world.previousPath == "README.md")
        #expect(hello.previousHash == nil)
        #expect(blame.commit.subject == "merge feature")
    }

    @Test func blameAtAnOlderRevisionAndKeepsBlankLines() throws {
        let repo = try TestRepo()
        try repo.write("notes.txt", "one\n\n\tthree\n")
        try repo.commit("first")
        try repo.write("notes.txt", "one\n\n\tthree\nfour\n")
        try repo.commit("second")
        let git = try GitRepository.discover(at: repo.url.path)

        #expect(try git.blame(path: "notes.txt", revision: "HEAD").lines.map(\.text) == ["one", "", "\tthree", "four"])
        #expect(try git.blame(path: "notes.txt", revision: "HEAD~1").lines.count == 3)
    }

    @Test func blameFollowsRenames() throws {
        let repo = try TestRepo.branchAndMerge()
        try repo.git("mv", "README.md", "DOCS.md")
        try repo.commit("rename readme")
        let blame = try GitRepository.discover(at: repo.url.path).blame(path: "DOCS.md", revision: "HEAD")

        let first = try #require(blame.commits[blame.lines[0].hash])
        #expect(first.summary == "init")
        #expect(first.filename == "README.md")
    }

    @Test func blameReportsAMissingPath() throws {
        let repo = try TestRepo.branchAndMerge()
        let git = try GitRepository.discover(at: repo.url.path)
        #expect(throws: GitRepository.GitError.self) { try git.blame(path: "nope.txt", revision: "HEAD") }
        #expect(throws: GitRepository.GitError.self) { try git.blame(path: "README.md", revision: "no-such-rev") }
    }

    @Test func listsFilesAtARevision() throws {
        let repo = try TestRepo.branchAndMerge()
        let git = try GitRepository.discover(at: repo.url.path)
        #expect(try git.files(at: "HEAD").sorted() == ["README.md", "feature.txt"])
        #expect(try git.files(at: "main~1") == ["README.md"])
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
