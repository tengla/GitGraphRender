import Foundation
import WebKit

/// The WebView → Swift bridge. JS posts a request to a named handler
/// (commit, author, revision, blame, files); we run `git` off the main thread
/// and reply by calling the matching `window.render…` function.
extension AppDelegate: WKScriptMessageHandler {

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        switch message.name {
        case "commit": handleCommitRequest(message.body)
        case "author": handleAuthorRequest(message.body)
        case "revision": handleRevisionRequest(message.body)
        case "blame": handleBlameRequest(message.body)
        case "files": handleFilesRequest(message.body)
        default: break
        }
    }

    /// JS asked for `git blame` → run it off-thread (it can take seconds on long
    /// histories) and hand the result, or an error, to `window.renderBlame`.
    /// The request id lets JS ignore replies it has since navigated away from.
    private func handleBlameRequest(_ body: Any) {
        guard let dict = body as? [String: Any],
              let id = (dict["id"] as? NSNumber)?.intValue,
              let revision = dict["revision"] as? String,
              let path = dict["path"] as? String else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var json = "null", message = "null"
            do {
                let result = try self.repo.blame(path: path, revision: revision)
                if let data = try? JSONEncoder().encode(result), let str = String(data: data, encoding: .utf8) {
                    json = str
                }
            } catch {
                message = Self.jsString(error.localizedDescription)
            }
            DispatchQueue.main.async {
                self.webView.evaluateJavaScript("window.renderBlame(\(id), \(json), \(message));",
                                                completionHandler: nil)
            }
        }
    }

    /// JS asked for a revision's file list → reply via `window.renderFileList`.
    private func handleFilesRequest(_ body: Any) {
        guard let revision = body as? String else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let files = (try? self.repo.files(at: revision)) ?? []
            let json = (try? JSONEncoder().encode(files)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            DispatchQueue.main.async {
                self.webView.evaluateJavaScript("window.renderFileList(\(Self.jsString(revision)), \(json));",
                                                completionHandler: nil)
            }
        }
    }

    /// JS asked to `git show` a revision → resolve it to a commit off-thread and
    /// hand it (or an error) to `window.renderRevision`. The panel then fetches
    /// the diff through the usual `commit` bridge.
    private func handleRevisionRequest(_ body: Any) {
        guard let revision = body as? String else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var json = "null", message = "null"
            do {
                let commit = try self.repo.commit(for: revision)
                if let data = try? JSONEncoder().encode(commit), let str = String(data: data, encoding: .utf8) {
                    json = str
                }
            } catch {
                message = Self.jsString(error.localizedDescription)
            }
            DispatchQueue.main.async {
                let js = "window.renderRevision(\(Self.jsString(revision)), \(json), \(message));"
                self.webView.evaluateJavaScript(js, completionHandler: nil)
            }
        }
    }

    /// JS asked for a commit's diff → run `git show` off-thread → render it.
    private func handleCommitRequest(_ body: Any) {
        guard let hash = body as? String else { return }
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

    /// JS asked for an author's activity → run `git log --all` off-thread (scoped
    /// to the loaded graph's date window), encode the report to JSON, and hand it
    /// to `window.renderAuthor`.
    private func handleAuthorRequest(_ body: Any) {
        // Payload is { email, since, until } — the email plus the loaded
        // graph's date window (Unix seconds) so the report is scoped to it.
        guard let dict = body as? [String: Any], let email = dict["email"] as? String else { return }
        let since = (dict["since"] as? NSNumber)?.doubleValue
        let until = (dict["until"] as? NSNumber)?.doubleValue
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let activity = self.repo.authorActivity(email: email, since: since, until: until)
            let json: String
            if let activity,
               let data = try? JSONEncoder().encode(activity),
               let str = String(data: data, encoding: .utf8) {
                json = str
            } else {
                json = "null"
            }
            DispatchQueue.main.async {
                let js = "window.renderAuthor(\(Self.jsString(email)), \(json));"
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
}
