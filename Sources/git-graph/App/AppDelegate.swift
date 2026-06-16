import AppKit
import WebKit

/// Owns the window and the WebView, loads the graph, and bridges the WebView's
/// "show me this commit's diff" requests back to `git`. Structurally this mirrors
/// MarkdownRender's AppDelegate (window + WKWebView + menu), with the markdown
/// pipeline swapped for the git pipeline.
final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler {
    private let repo: GitRepository
    private let theme: String
    private let maxCount: Int
    private let allBranches: Bool
    private let watchEnabled: Bool

    private var window: NSWindow!
    private var webView: WKWebView!
    private var watchSource: DispatchSourceFileSystemObject?

    init(repo: GitRepository, theme: String, maxCount: Int, allBranches: Bool, watchEnabled: Bool) {
        self.repo = repo
        self.theme = theme
        self.maxCount = maxCount
        self.allBranches = allBranches
        self.watchEnabled = watchEnabled
        super.init()
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupWindow()
        setupWebView()
        setupMenu()
        loadGraph()

        if watchEnabled { setupWatcher() }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(webView)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        watchSource?.cancel()
    }

    // MARK: - Window & WebView

    private func setupWindow() {
        let screenSize = NSScreen.main?.frame.size ?? CGSize(width: 1200, height: 800)
        let width: CGFloat = min(1000, screenSize.width * 0.75)
        let height: CGFloat = min(760, screenSize.height * 0.85)
        let rect = NSRect(x: (screenSize.width - width) / 2,
                          y: (screenSize.height - height) / 2,
                          width: width, height: height)

        window = NSWindow(contentRect: rect,
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = repo.repoName + " — git graph"
        window.minSize = NSSize(width: 520, height: 360)
        window.isReleasedWhenClosed = false

        switch theme {
        case "light": window.appearance = NSAppearance(named: .aqua)
        case "dark":  window.appearance = NSAppearance(named: .darkAqua)
        default:      window.appearance = nil   // follow system
        }
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        // Bridge: JS posts a commit hash → we reply with its diff.
        config.userContentController.add(self, name: "commit")

        webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        window.contentView = webView
    }

    // MARK: - Loading

    private func loadGraph() {
        do {
            let (rawCommits, total) = try repo.loadCommits(maxCount: maxCount, allBranches: allBranches)
            let (commits, totalLanes) = GraphLayout.assign(rawCommits)
            let graph = GraphData(
                commits: commits,
                totalLanes: totalLanes,
                shownCount: commits.count,
                totalCount: total,
                repoName: repo.repoName,
                truncated: commits.count < total
            )

            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(graph)
            let json = String(data: jsonData, encoding: .utf8) ?? "{}"

            let html = HTMLGenerator.generateHTML(graphJSON: json, theme: theme)
            webView.loadHTMLString(html, baseURL: repo.topLevel)
        } catch {
            let html = HTMLGenerator.generateErrorHTML(error: error.localizedDescription)
            webView.loadHTMLString(html, baseURL: repo.topLevel)
        }
    }

    @objc private func reload() { loadGraph() }

    // MARK: - WKScriptMessageHandler (commit diff bridge)

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "commit", let hash = message.body as? String else { return }
        // Fetch off the main thread; git can be slow on big commits.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let diff = self.repo.diff(for: hash)
            DispatchQueue.main.async {
                let js = "window.renderDiff(\(Self.jsString(hash)), \(Self.jsString(diff)));"
                self.webView.evaluateJavaScript(js, completionHandler: nil)
            }
        }
    }

    /// JSON-encodes a Swift string into a JS string literal (handles quotes,
    /// newlines, backslashes, unicode) so it can be safely interpolated into JS.
    private static func jsString(_ s: String) -> String {
        if let data = try? JSONEncoder().encode(s), let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "\"\""
    }

    // MARK: - Menu

    private func setupMenu() {
        let mainMenu = NSMenu()

        // Helper: add an item whose action targets *this* delegate explicitly.
        // Without an explicit target, AppKit routes the action down the responder
        // chain, where the first-responder WKWebView intercepts methods it also
        // implements. In particular `reload(_:)` is a real WKWebView action — so
        // ⌘R would reload the WebView's (non-navigable loadHTMLString) document
        // and blank the window instead of calling our loadGraph(). Pinning the
        // target to self prevents that.
        func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String,
                 modifiers: NSEvent.ModifierFlags = .command) {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.target = self
            item.keyEquivalentModifierMask = modifiers
        }

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        add(appMenu, "About git-graph", #selector(showAbout), "")
        appMenu.addItem(.separator())
        // Quit legitimately targets NSApp via the responder chain — leave it.
        appMenu.addItem(withTitle: "Quit git-graph", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        add(viewMenu, "Reload", #selector(reload), "r")
        add(viewMenu, "Find…", #selector(find), "f")
        viewMenu.addItem(.separator())
        add(viewMenu, "Actual Size", #selector(resetZoom), "0")
        add(viewMenu, "Zoom In", #selector(zoomIn), "+")
        add(viewMenu, "Zoom Out", #selector(zoomOut), "-")
        viewItem.submenu = viewMenu
        mainMenu.addItem(viewItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "git-graph"
        alert.informativeText = "A beautiful, interactive git history viewer for macOS."
        alert.alertStyle = .informational
        alert.runModal()
    }

    @objc private func find() {
        webView.evaluateJavaScript("window.gitGraph && window.gitGraph.openSearch();", completionHandler: nil)
    }

    @objc private func resetZoom() { webView.pageZoom = 1.0 }
    @objc private func zoomIn() { webView.pageZoom += 0.1 }
    @objc private func zoomOut() { webView.pageZoom = max(0.5, webView.pageZoom - 0.1) }

    // MARK: - Watch mode

    /// Watches `.git/HEAD` for writes (commit / checkout / reset all touch it) and
    /// auto-reloads. Mirrors MarkdownRender's DispatchSource file watcher.
    private func setupWatcher() {
        let headPath = repo.topLevel.appendingPathComponent(".git/HEAD").path
        let fd = open(headPath, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self?.loadGraph() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watchSource = source
    }
}
