import AppKit
import WebKit

@MainActor
@Observable
final class ProfileSession {
    private static let cookieAutosaveDelay = Duration.seconds(2)

    let name: String
    let dataStore: WKWebsiteDataStore
    let history: HistoryStore
    let downloads: DownloadManager
    let supervisor: Supervisor
    let events: EventBus
    @ObservationIgnored private var cookies: CookieObserver?
    let settings: ProfileSettingsStore
    let proxy: NetworkProxy
    @ObservationIgnored let setPaused: (Bool) -> Void
    @ObservationIgnored let profileNames: () -> [String]
    @ObservationIgnored var onClose: (() -> Void)?
    @ObservationIgnored private(set) var contentRules: WKContentRuleList?
    @ObservationIgnored let precise = PrecisePool()
    @ObservationIgnored private let restore: TabRestoreStore
    @ObservationIgnored let atlas: SiteAtlasStore
    @ObservationIgnored private let sessionCookies: SessionCookieStore
    @ObservationIgnored let storageKey: Data
    @ObservationIgnored private var restoreBook = TabRestoreBook()
    @ObservationIgnored private var rulesJSON: String?
    @ObservationIgnored private var discardsTabs = false
    @ObservationIgnored private(set) var isClosed = false
    @ObservationIgnored private lazy var warmer = ModelWarmer(session: self)
    @ObservationIgnored private lazy var cookieAutosave = Coalescer(delay: Self.cookieAutosaveDelay) { [weak self] in await self?.saveSessionCookies() }
    @ObservationIgnored var lastChange: Bool?
    @ObservationIgnored var liveFile: URL?
    var isBackground = false
    private(set) var contentRuleError: String?
    private(set) var tabs: [BrowserWindowController] = []
    private(set) var selectedTab: BrowserWindowController?

    init(
        name: String,
        dataStore: WKWebsiteDataStore,
        history: HistoryStore,
        downloads: DownloadManager,
        events: EventBus,
        settings: ProfileSettingsStore,
        restore: TabRestoreStore,
        atlas: SiteAtlasStore,
        sessionCookies: SessionCookieStore,
        storageKey: Data,
        policy: Policy,
        rules: RuleStore,
        setPaused: @escaping (Bool) -> Void,
        profileNames: @escaping () -> [String]
    ) throws {
        self.name = name
        self.dataStore = dataStore
        self.history = history
        self.downloads = downloads
        self.events = events
        self.settings = settings
        self.restore = restore
        self.atlas = atlas
        self.sessionCookies = sessionCookies
        self.storageKey = storageKey
        self.supervisor = Supervisor(policy: policy, rules: rules, events: events)
        self.setPaused = setPaused
        self.profileNames = profileNames
        proxy = try NetworkProxy(rules: settings.settings.hostRules)
        cookies = CookieObserver(store: dataStore.httpCookieStore, events: events) { [weak self] in self?.cookieAutosave.schedule() }
    }

    var lastActivity: ContinuousClock.Instant? {
        [events.lastReaction, proxy.lastTraffic].compactMap { $0 }.max()
    }

    func emit(_ type: EventType, from tab: BrowserWindowController?, _ fields: [String: String] = [:]) {
        events.emit(type, tab: tab.flatMap(index(of:)), fields)
        if type == .navigationFinished {
            cookieAutosave.schedule()
        }
    }

    var actions: ActionPipeline {
        ActionPipeline(session: self)
    }

    var preciseReport: String {
        PreciseStatus.report(enabled: settings.settings.preciseMode, tabs: tabs.map(\.preciseStatus))
    }

    func index(of tab: BrowserWindowController) -> Int? {
        tabs.firstIndex { $0 === tab }.map { $0 + 1 }
    }

    func prepare() async throws {
        await sessionCookies.restore(into: dataStore.httpCookieStore)
        dataStore.proxyConfigurations = [try await proxy.start()]
        await updateContentRules()
        observeSettings()
        warmer.start()
    }

    func resume(fallback: URL?) {
        let saved = restore.load()
        guard !saved.isEmpty else {
            newTab(fallback)
            return
        }
        saved.forEach { newTab(restoring: $0) }
    }

    func saveSessionCookies() async {
        guard !discardsTabs else { return }
        await sessionCookies.save(from: dataStore.httpCookieStore)
    }

    func saveTabs() {
        guard !discardsTabs, !tabs.isEmpty else { return }
        restore.save(tabs.compactMap(\.savedTab))
    }

    @discardableResult
    func newTab(_ url: URL? = nil, configuration: WKWebViewConfiguration? = nil, restoring saved: SavedTab? = nil) -> BrowserWindowController {
        let tab = BrowserWindowController(session: self, configuration: configuration)
        tab.setBackground(isBackground)
        if let anchor = selectedTab?.window, let window = tab.window {
            anchor.addTabbedWindow(window, ordered: .above)
        }
        tabs.append(tab)
        emit(.tabOpened, from: tab, url.map { ["url": $0.absoluteString] } ?? [:])
        select(tab)
        if !isBackground, tab.window?.tabGroup?.isTabBarVisible == false {
            tab.window?.toggleTabBar(nil)
        }
        if let saved {
            tab.restore(saved)
        } else if let url {
            tab.load(url)
        } else if configuration == nil {
            tab.focusAddressBar(nil)
        }
        return tab
    }

    func setBackground(_ background: Bool) {
        isBackground = background
        tabs.forEach { $0.setBackground(background) }
    }

    func select(_ tab: BrowserWindowController) {
        markSelected(tab)
        tab.window?.tabGroup?.selectedWindow = tab.window
        guard !isBackground else { return }
        tab.showWindow(nil)
        if !NSApp.isActive {
            tab.window?.orderFrontRegardless()
        }
    }

    func bringToFront() {
        selectedTab.map(select)
    }

    func tabDidBecomeKey(_ tab: BrowserWindowController) {
        markSelected(tab)
        UserDefaults.standard.set(name, forKey: Workspace.lastProfileKey)
    }

    private func markSelected(_ tab: BrowserWindowController) {
        guard selectedTab !== tab else { return }
        selectedTab = tab
        emit(.tabSelected, from: tab)
    }

    func tabDidClose(_ tab: BrowserWindowController) {
        emit(.tabClosed, from: tab, tab.webView.url.map { ["url": $0.absoluteString] } ?? [:])
        let startsClosing = !discardsTabs && restoreBook.willClose(tabs.compactMap(\.savedTab))
        tabs.removeAll { $0 === tab }
        if selectedTab === tab {
            selectedTab = tabs.last
        }
        if startsClosing {
            Task { @MainActor in settleClosedTabs() }
        }
        if tabs.isEmpty {
            supervisor.resolve(false)
            isClosed = true
            warmer.stop()
            proxy.stop()
            onClose?()
        }
    }

    func closeAll() {
        discardsTabs = true
        tabs.forEach { $0.close() }
    }

    private func settleClosedTabs() {
        let saved = restoreBook.settle(remaining: tabs.compactMap(\.savedTab))
        guard !discardsTabs else { return }
        restore.save(saved)
    }

    private func observeSettings() {
        withObservationTracking {
            _ = settings.settings
        } onChange: { [weak self] in
            Task { @MainActor in self?.settingsDidChange() }
        }
    }

    private func settingsDidChange() {
        guard !isClosed else { return }
        observeSettings()
        proxy.update(settings.settings.hostRules)
        tabs.forEach { $0.applySettings() }
        Task { await updateContentRules() }
    }

    private func updateContentRules() async {
        let json = ContentRules.json(for: settings.settings)
        guard json != rulesJSON else { return }
        rulesJSON = json
        do {
            let compiled = if let json { try await ContentRuleCompiler.compile(json) } else { WKContentRuleList?.none }
            guard rulesJSON == json else { return }
            contentRules = compiled
            contentRuleError = nil
        } catch {
            guard rulesJSON == json else { return }
            contentRuleError = error.localizedDescription
        }
        tabs.forEach { $0.applyContentRules() }
    }

    func fenceRefusal(for url: URL) -> String? {
        supervisor.rules.rules.fenceRefusal(for: url)
    }

    func signature(of tab: BrowserWindowController) -> PageSignature? {
        PageSignature(url: tab.webView.url, title: tab.webView.title)
    }
}
