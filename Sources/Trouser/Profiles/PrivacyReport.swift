import Foundation

struct PrivacyReport: Codable, Equatable, Sendable {
    struct Site: Codable, Equatable, Identifiable, Sendable {
        let name: String
        let dataTypes: [String]
        let cookies: Int

        var id: String { name }
    }

    let sites: [Site]

    var cookies: Int {
        sites.map(\.cookies).reduce(0, +)
    }

    init(sites: [Site]) {
        self.sites = sites
    }

    init(records: [(name: String, types: Set<String>)], cookieDomains: [String]) {
        let domains = cookieDomains.map(HostRules.normalize).map { $0.hasPrefix(".") ? String($0.dropFirst()) : $0 }
        sites = records.map { record in
            let site = HostRules.normalize(record.name)
            return Site(
                name: record.name,
                dataTypes: record.types.map(Self.displayName).sorted(),
                cookies: domains.filter { HostRules.matches($0, pattern: site) }.count
            )
        }
        .sorted { ($0.cookies, $1.name) > ($1.cookies, $0.name) }
    }

    static func displayName(_ type: String) -> String {
        names[type] ?? type.replacingOccurrences(of: "WKWebsiteDataType", with: "")
    }

    private static let names = [
        "WKWebsiteDataTypeCookies": "Cookies",
        "WKWebsiteDataTypeDiskCache": "Disk cache",
        "WKWebsiteDataTypeMemoryCache": "Memory cache",
        "WKWebsiteDataTypeFetchCache": "Fetch cache",
        "WKWebsiteDataTypeOfflineWebApplicationCache": "App cache",
        "WKWebsiteDataTypeLocalStorage": "Local storage",
        "WKWebsiteDataTypeSessionStorage": "Session storage",
        "WKWebsiteDataTypeIndexedDBDatabases": "IndexedDB",
        "WKWebsiteDataTypeWebSQLDatabases": "WebSQL",
        "WKWebsiteDataTypeServiceWorkerRegistrations": "Service workers",
        "WKWebsiteDataTypeFileSystem": "File system",
        "WKWebsiteDataTypeSearchFieldRecentSearches": "Recent searches",
        "WKWebsiteDataTypeMediaKeys": "Media keys",
        "WKWebsiteDataTypeHashSalt": "Hash salt",
        "WKWebsiteDataTypeScreenTime": "Screen Time"
    ]
}
