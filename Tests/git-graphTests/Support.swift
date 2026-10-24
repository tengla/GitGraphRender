import Foundation

/// Output of a finished child process.
struct ProcessResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

/// Runs `executable` to completion and captures its output.
@discardableResult
func runProcess(_ executable: URL, _ arguments: [String],
                in directory: URL? = nil,
                environment: [String: String]? = nil) throws -> ProcessResult {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    if let directory { process.currentDirectoryURL = directory }
    if let environment {
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
    }
    let stdout = Pipe(), stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    // Read both pipes before waiting to avoid deadlock on large output.
    let out = stdout.fileHandleForReading.readDataToEndOfFile()
    let err = stderr.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return ProcessResult(status: process.terminationStatus,
                         stdout: String(decoding: out, as: UTF8.self),
                         stderr: String(decoding: err, as: UTF8.self))
}

/// Makes a fresh, empty temporary directory.
func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("git-graph-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A throwaway git repository in a temp directory.
///
/// git runs isolated from the user's global/system config (so signing, hooks,
/// aliases etc. can't interfere) with a fixed identity and commit dates.
final class TestRepo {
    let url: URL
    private var clock = 1_700_000_000

    init() throws {
        url = try makeTempDirectory()
        try git("init", "-q", "-b", "main")
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    @discardableResult
    func git(_ arguments: String...) throws -> String {
        let date = "\(clock) +0000"
        let result = try runProcess(URL(fileURLWithPath: "/usr/bin/env"), ["git"] + arguments,
                                    in: url,
                                    environment: [
                                        "GIT_CONFIG_GLOBAL": "/dev/null",
                                        "GIT_CONFIG_NOSYSTEM": "1",
                                        "GIT_AUTHOR_NAME": "Test Author",
                                        "GIT_AUTHOR_EMAIL": "author@example.com",
                                        "GIT_COMMITTER_NAME": "Test Author",
                                        "GIT_COMMITTER_EMAIL": "author@example.com",
                                        "GIT_AUTHOR_DATE": date,
                                        "GIT_COMMITTER_DATE": date
                                    ])
        guard result.status == 0 else {
            let command = "git " + arguments.joined(separator: " ")
            throw NSError(domain: "TestRepo", code: Int(result.status),
                          userInfo: [NSLocalizedDescriptionKey: "\(command): \(result.stderr)"])
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func write(_ name: String, _ contents: String) throws {
        try write(name, Data(contents.utf8))
    }

    func write(_ name: String, _ data: Data) throws {
        let file = url.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: file)
    }

    /// Stages everything and commits; returns the new commit's hash.
    @discardableResult
    func commit(_ message: String) throws -> String {
        clock += 60
        try git("add", "-A")
        try git("commit", "-q", "-m", message)
        return try git("rev-parse", "HEAD")
    }

    /// main: init → main work → merge(feature) [tag v1.0]; feature: one commit off init.
    static func branchAndMerge() throws -> TestRepo {
        let repo = try TestRepo()
        try repo.write("README.md", "hello\n")
        try repo.commit("init")
        try repo.git("checkout", "-q", "-b", "feature")
        try repo.write("feature.txt", "feature work\n")
        try repo.commit("feature work")
        try repo.git("checkout", "-q", "main")
        try repo.write("README.md", "hello\nworld\n")
        try repo.commit("main work")
        try repo.git("merge", "-q", "--no-ff", "feature", "-m", "merge feature")
        try repo.git("tag", "v1.0")
        return repo
    }
}
