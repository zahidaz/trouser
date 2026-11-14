import Foundation
import WebKit

struct SavedCookie: Codable, Equatable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let secure: Bool
    let httpOnly: Bool
    let sameSite: String?

    init(_ cookie: HTTPCookie) {
        name = cookie.name
        value = cookie.value
        domain = cookie.domain
        path = cookie.path
        secure = cookie.isSecure
        httpOnly = cookie.isHTTPOnly
        sameSite = cookie.sameSitePolicy?.rawValue
    }

    var cookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: path]
        if secure { properties[.secure] = "TRUE" }
        if httpOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
        if let sameSite { properties[.sameSitePolicy] = sameSite }
        return HTTPCookie(properties: properties)
    }
}

@MainActor
struct SessionCookieStore {
    let fileURL: URL

    func save(from store: WKHTTPCookieStore) async {
        write(await store.allCookies())
    }

    func restore(into store: WKHTTPCookieStore) async {
        for cookie in load() {
            await store.setCookie(cookie)
        }
    }

    func write(_ cookies: [HTTPCookie]) {
        let saved = cookies.filter(\.isSessionOnly).map(SavedCookie.init)
        guard !saved.isEmpty, let data = try? JSONEncoder().encode(saved) else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        guard (try? Data(contentsOf: fileURL)) != data else { return }
        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    func load() -> [HTTPCookie] {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode([SavedCookie].self, from: data)
        else { return [] }
        return saved.compactMap(\.cookie)
    }
}
