import Foundation
import WebKit

extension BrowserWindowController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        navigationStart = .now
        emit(.navigationStarted, urlFields)
    }

    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        emit(.navigationRedirected, urlFields)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        updateState()
        emit(.navigationCommitted, urlFields)
        PageObserver.certificate(of: webView).map { emit(.pageCertificate, $0) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateState()
        reloadedAfterTermination = false
        precise?.navigationFinished()
        emit(.navigationFinished, urlFields.merging(elapsed) { $1 })
        if let url = webView.url {
            session.history.record(url, title: webView.title ?? "")
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        emit(.navigationFailed, urlFields.merging(elapsed) { $1 }.merging(failure(error)) { $1 })
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let failed = ((error as NSError).userInfo[NSURLErrorFailingURLErrorKey] as? URL)?.absoluteString
        let fields = failure(error).merging(["url": failed ?? webView.url?.absoluteString ?? ""]) { $1 }
        emit(.navigationFailed, fields.merging(elapsed) { $1 })
    }

    @objc(_webCryptoMasterKeyForWebView:)
    func storageKey(for webView: WKWebView) -> Data {
        session.storageKey
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        emit(.processTerminated, urlFields)
        if let precise {
            precise.processTerminated()
            session.precise.disable("a Precise mode web content process stopped; new tabs use the capture model until the profile reopens")
        }
        guard !reloadedAfterTermination else { return }
        reloadedAfterTermination = true
        webView.reload()
        emit(.processReloaded, urlFields)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences
    ) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        let settings = session.settings.settings
        preferences.allowsContentJavaScript = settings.javaScript
        if settings.lockdownMode {
            preferences.isLockdownModeEnabled = true
        }
        if let mode = settings.contentMode.webKit {
            preferences.preferredContentMode = mode
        }
        return (await policy(for: navigationAction), preferences)
    }

    private func policy(for navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        let target = navigationAction.request.url?.host() ?? "page"
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        if isMainFrame, let url = navigationAction.request.url, !admitsNavigation(to: url) {
            return .cancel
        }
        if navigationAction.shouldPerformDownload {
            return await authorizeIfActing(.download, "download from \(target)") ? .download : .cancel
        }
        guard navigationAction.request.httpMethod == "POST", isMainFrame else { return .allow }
        return await authorizeIfActing(.submit, "submit form to \(target)") ? .allow : .cancel
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse
    ) async -> WKNavigationResponsePolicy {
        let http = navigationResponse.response as? HTTPURLResponse
        emit(.navigationResponse, [
            "url": navigationResponse.response.url?.absoluteString ?? "",
            "status": http.map { "\($0.statusCode)" } ?? "none",
            "mime": navigationResponse.response.mimeType ?? "unknown",
            "frame": navigationResponse.isForMainFrame ? "main" : "sub"
        ])
        let disposition = http?.value(forHTTPHeaderField: "Content-Disposition")
        let isAttachment = disposition?.lowercased().hasPrefix("attachment") ?? false
        guard isAttachment || !navigationResponse.canShowMIMEType else { return .allow }
        let name = navigationResponse.response.suggestedFilename ?? "file"
        return await authorizeIfActing(.download, "download \(name)") ? .download : .cancel
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        session.downloads.track(download)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        session.downloads.track(download)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url, !admitsNavigation(to: url) {
            return nil
        }
        emit(.popup, ["url": navigationAction.request.url?.absoluteString ?? ""])
        return session.newTab(configuration: configuration).webView
    }

    private var urlFields: [String: String] {
        ["url": webView.url?.absoluteString ?? ""]
    }

    private var elapsed: [String: String] {
        guard let navigationStart else { return [:] }
        let duration = ContinuousClock.now - navigationStart
        return ["duration": "\(Int(duration / .milliseconds(1)))ms"]
    }

    private func failure(_ error: Error) -> [String: String] {
        let error = error as NSError
        return ["error": error.localizedDescription, "code": "\(error.code)"]
    }

    private func admitsNavigation(to url: URL) -> Bool {
        guard session.supervisor.isActing, let reason = session.fenceRefusal(for: url) else { return true }
        session.supervisor.refuse(.navigate, "navigate to \(url.host() ?? url.absoluteString)", reason: reason)
        return false
    }

    private func authorizeIfActing(_ kind: ActionKind, _ summary: String) async -> Bool {
        let supervisor = session.supervisor
        guard supervisor.isActing else { return true }
        switch await supervisor.authorize(kind, summary) {
        case .granted(let entry):
            supervisor.finish(entry, .done)
            return true
        case .refused:
            return false
        }
    }

    private func updateState() {
        pageModel.invalidate()
        state.url = webView.url
        state.title = webView.title.flatMap { $0.isEmpty ? nil : $0 } ?? webView.url?.host() ?? "Start Page"
        startPage.isHidden = webView.url != nil
        addressField.url = webView.url
        window?.title = state.title
        updateNavigationButtons()
    }
}
