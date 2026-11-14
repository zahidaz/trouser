import WebKit

@MainActor
final class CookieObserver: NSObject, WKHTTPCookieStoreObserver {
    private let store: WKHTTPCookieStore
    private let events: EventBus
    private let onChange: @MainActor () -> Void
    private lazy var report = Coalescer(delay: .milliseconds(100)) { [weak self] in await self?.emitCount() }

    init(store: WKHTTPCookieStore, events: EventBus, onChange: @escaping @MainActor () -> Void) {
        self.store = store
        self.events = events
        self.onChange = onChange
        super.init()
        store.add(self)
    }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        report.schedule()
        onChange()
    }

    private func emitCount() async {
        let count = await store.allCookies().count
        events.emit(.cookiesChanged, ["count": "\(count)"])
    }
}
