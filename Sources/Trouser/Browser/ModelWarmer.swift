import Foundation

@MainActor
final class ModelWarmer {
    private weak var session: ProfileSession?
    private var task: Task<Void, Never>?
    private var interval = ModelWarmer.shortestInterval

    static let debounce: Duration = .milliseconds(120)
    static let longestDebounce: Duration = .seconds(1)
    static let shortestInterval: Duration = .seconds(1)
    static let longestInterval: Duration = .seconds(8)

    init(session: ProfileSession) {
        self.session = session
    }

    func start() {
        task = Task { [weak self] in
            while !Task.isCancelled, let events = self?.session?.events {
                await events.next(within: self?.interval ?? Self.longestInterval)
                await self?.cycle()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func cycle() async {
        await debounce()
        guard let session, let tab = session.selectedTab, Self.shouldWarm(tab: tab, session: session) else { return }
        let before = tab.pageModel.latest
        guard let model = try? await tab.pageModel.refresh() else { return }
        let unchanged = before.map { ModelDiff(from: $0, to: model).isEmpty } ?? false
        interval = Self.interval(after: interval, unchanged: unchanged)
    }

    static func interval(after interval: Duration, unchanged: Bool) -> Duration {
        unchanged ? min(interval * 2, longestInterval) : shortestInterval
    }

    private func debounce() async {
        let start = ContinuousClock.now
        while let session, let last = session.lastActivity {
            let now = ContinuousClock.now
            let quiet = now - last
            guard quiet < Self.debounce, now - start < Self.longestDebounce else { return }
            await session.events.next(within: Self.debounce - quiet)
        }
    }

    private static func shouldWarm(tab: BrowserWindowController, session: ProfileSession) -> Bool {
        tab.webView.url != nil
            && !tab.webView.isLoading
            && !session.supervisor.isBusy
            && !tab.pageModel.isRendering
            && !tab.pageModel.isCurrent
    }
}
