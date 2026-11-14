import AppKit
import SwiftUI
import WebKit

@MainActor
final class BrowserWindowController: NSWindowController, NSWindowDelegate {
    let driver: PageDriver
    let pageModel: PageModelStore
    let dialogs = DialogGate()
    let marker = MarkerView()
    let state = TabState()
    let webView: WKWebView
    let addressField = AddressField()
    let session: ProfileSession
    let precise: PreciseLink?
    private let preciseSelection: PreciseStatus
    let startPage: NSView
    let pageView = NSView()
    var stage: StageWindow?
    private var pageObserver: PageObserver?
    var navigationStart: ContinuousClock.Instant?
    var reloadedAfterTermination = false
    private var observations: [NSKeyValueObservation] = []
    var webViewConstraints: [NSLayoutConstraint] = []

    init(session: ProfileSession, configuration: WKWebViewConfiguration? = nil) {
        self.session = session

        let inherited = configuration != nil
        let configuration = configuration ?? WKWebViewConfiguration()
        preciseSelection = session.precise.attach(configuration, enabled: session.settings.settings.preciseMode, inherited: inherited)
        configuration.websiteDataStore = session.dataStore
        configuration.applicationNameForUserAgent = SafariIdentity.applicationName
        configuration.upgradeKnownHostsToHTTPS = true
        configuration.preferences.isFraudulentWebsiteWarningEnabled = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.preferences.inactiveSchedulingPolicy = session.settings.settings.inactiveScheduling.webKit
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isInspectable = session.supervisor.policy.allowsWebInspector
        webView.allowsBackForwardNavigationGestures = true
        driver = PageDriver(webView: webView)
        precise = preciseSelection == .connecting ? PreciseLink(webView: webView) : nil
        pageModel = PageModelStore(driver: driver, dialogs: dialogs, precise: precise, unlinked: preciseSelection) { [weak session] in session?.lastActivity }

        let startPage = NSHostingView(rootView: StartView(session: session))
        startPage.sizingOptions = []
        self.startPage = startPage

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.tabbingIdentifier = "trouser.\(session.name)"
        window.tabbingMode = .preferred
        window.title = "Start Page"
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.contentMinSize = NSSize(width: 760, height: 480)
        super.init(window: window)

        window.delegate = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
        addressField.target = self
        addressField.action = #selector(submitAddress)
        window.contentViewController = makeSplitViewController()
        window.toolbar = makeToolbar()
        window.setFrame(NSScreen.main?.visibleFrame ?? window.frame, display: false)
        pageObserver = PageObserver(webView: webView) { [unowned self] type, fields in emit(type, fields) }
        precise?.emit = { [unowned self] type, fields in emit(type, fields) }
        if case .unavailable(let reason) = preciseSelection {
            emit(.pagePrecise, ["mode": "fallback", "reason": reason])
        }
        observations = [
            webView.observe(\.url) { [weak self] _, _ in MainActor.assumeIsolated { self?.pageModel.invalidate() } },
            webView.observe(\.title) { [weak self] _, _ in MainActor.assumeIsolated { self?.pageModel.invalidate() } }
        ]
        applySettings()
        applyContentRules()
    }

    required init?(coder: NSCoder) {
        nil
    }

    var elementActions: ElementActions {
        ElementActions(driver: driver, models: pageModel)
    }

    var preciseStatus: PreciseStatus {
        precise?.status ?? preciseSelection
    }

    func label(at point: CGPoint) async throws -> String? {
        if let label = await precise?.label(at: point) {
            return label
        }
        return try await pageModel.current().element(at: point)?.label
    }

    var savedTab: SavedTab? {
        guard let url = webView.url else { return nil }
        return SavedTab(url: url, title: state.title, state: webView.interactionState as? Data)
    }

    func applySettings() {
        let settings = session.settings.settings
        webView.customUserAgent = settings.customUserAgent
        webView.pageZoom = settings.pageZoom
        layoutWebView()
    }

    func applyContentRules() {
        let controller = webView.configuration.userContentController
        controller.removeAllContentRuleLists()
        session.contentRules.map(controller.add)
    }

    func restore(_ saved: SavedTab) {
        startPage.isHidden = true
        state.url = saved.url
        state.title = saved.title
        window?.title = saved.title
        if let data = saved.state {
            webView.interactionState = data
        } else {
            webView.load(URLRequest(url: saved.url))
        }
    }

    func load(_ url: URL) {
        startPage.isHidden = true
        webView.load(URLRequest(url: url))
    }

    @objc func goBack(_ sender: Any?) {
        webView.goBack()
    }

    @objc func goForward(_ sender: Any?) {
        webView.goForward()
    }

    @objc func reload(_ sender: Any?) {
        webView.reload()
    }

    @objc func showStartPage(_ sender: Any?) {
        startPage.isHidden = false
        addressField.url = nil
        window?.title = "Start Page"
        focusAddressBar(nil)
    }

    @objc func focusAddressBar(_ sender: Any?) {
        window?.makeFirstResponder(addressField)
    }

    @objc func navigate(_ sender: NSToolbarItemGroup) {
        if sender.selectedIndex == 0 {
            webView.goBack()
        } else {
            webView.goForward()
        }
    }

    override func newWindowForTab(_ sender: Any?) {
        session.newTab()
    }

    @objc private func submitAddress() {
        guard let url = URL(userInput: addressField.stringValue) else { return }
        load(url)
        window?.makeFirstResponder(webView)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        session.tabDidBecomeKey(self)
    }

    func windowWillClose(_ notification: Notification) {
        precise?.close()
        session.tabDidClose(self)
    }

    func emit(_ type: EventType, _ fields: [String: String]) {
        session.emit(type, from: self, fields)
    }
}
