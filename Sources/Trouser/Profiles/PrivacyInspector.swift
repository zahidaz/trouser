import WebKit

@MainActor
enum PrivacyInspector {
    static func report(for store: WKWebsiteDataStore) async -> PrivacyReport {
        let records = await store.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        let cookies = await store.httpCookieStore.allCookies()
        return PrivacyReport(
            records: records.map { (name: $0.displayName, types: $0.dataTypes) },
            cookieDomains: cookies.map(\.domain)
        )
    }

    static func remove(site: String, from store: WKWebsiteDataStore) async {
        let records = await store.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
            .filter { $0.displayName == site }
        guard !records.isEmpty else { return }
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: records)
    }
}
