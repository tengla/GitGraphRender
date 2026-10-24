import Foundation
import JavaScriptCore
import Testing
@testable import git_graph

@Suite struct HTMLGeneratorTests {

    /// The JS lives in a Swift string literal, where a missed `\\` escape
    /// silently produces broken JS. Parse it (without running it — it needs a
    /// DOM) by wrapping it in a function that is never called.
    @Test func embeddedJavaScriptParses() {
        let context = JSContext()!
        var error: String?
        context.exceptionHandler = { _, exception in error = exception?.toString() }
        context.evaluateScript("function __syntaxCheck() {\n\(HTMLGenerator.generateJS())\n}")
        #expect(error == nil)
    }

    /// The same path AppDelegate.loadGraph() takes: git log → layout → JSON → HTML.
    @Test func rendersARepositoryEndToEnd() throws {
        let repo = try TestRepo.branchAndMerge()
        let git = try GitRepository.discover(at: repo.url.path)
        let (raw, total) = try git.loadCommits(maxCount: 100, allBranches: true)
        let (commits, lanes) = GraphLayout.assign(raw)
        let graph = GraphData(commits: commits, totalLanes: lanes, shownCount: commits.count,
                              totalCount: total, repoName: git.repoName, truncated: false)
        let json = try #require(String(data: JSONEncoder().encode(graph), encoding: .utf8))

        let html = HTMLGenerator.generateHTML(graphJSON: json, theme: "auto")

        #expect(html.hasPrefix("<!DOCTYPE html>"))
        #expect(html.contains("const GRAPH_DATA = \(json);"))
        #expect(html.contains("merge feature"))
        #expect(html.contains("window.renderDiff"))
        #expect(lanes == 2)
    }
}
