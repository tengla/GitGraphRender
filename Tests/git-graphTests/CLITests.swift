import Foundation
import Testing

/// Runs the real `git-graph` binary. These only exercise paths that exit before
/// a window opens (help, argument validation, repo discovery).
@Suite struct CLITests {

    /// `swift test` builds the executable next to the test bundle.
    static let binary: URL = {
        let products = Bundle.allBundles
            .first { $0.bundlePath.hasSuffix(".xctest") }?
            .bundleURL.deletingLastPathComponent()
            ?? URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent(".build/debug")
        return products.appendingPathComponent("git-graph")
    }()

    @Test func binaryIsBuilt() {
        #expect(FileManager.default.isExecutableFile(atPath: Self.binary.path))
    }

    @Test func helpPrintsUsageAndExitsCleanly() throws {
        let result = try runProcess(Self.binary, ["--help"])
        #expect(result.status == 0)
        #expect(result.stdout.contains("USAGE: git-graph"))
        for option in ["--theme", "--max", "--all", "--watch"] {
            #expect(result.stdout.contains(option), "help should list \(option)")
        }
    }

    @Test func rejectsADirectoryThatIsNotARepository() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = try runProcess(Self.binary, [dir.path])
        #expect(result.status != 0)
        #expect(result.stderr.contains("Not a git repository"))
    }

    @Test(arguments: [
        (["--theme", "neon"], "Theme must be"),
        (["--max", "0"], "--max must be a positive number")
    ])
    func rejectsInvalidOptions(arguments: [String], message: String) throws {
        let repo = try TestRepo.branchAndMerge()
        let result = try runProcess(Self.binary, arguments + [repo.url.path])
        #expect(result.status != 0)
        #expect(result.stderr.contains(message))
    }
}
