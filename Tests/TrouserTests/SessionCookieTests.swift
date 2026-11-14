import Foundation
import Testing
@testable import Trouser

struct SessionCookieTests {
    @Test func roundTripsASessionCookie() throws {
        let original = try #require(HTTPCookie(properties: [
            .name: "session", .value: "abc", .domain: ".upwork.com", .path: "/",
            .secure: "TRUE", HTTPCookiePropertyKey("HttpOnly"): "TRUE", .sameSitePolicy: "lax"
        ]))
        let decoded = try JSONDecoder().decode(SavedCookie.self, from: JSONEncoder().encode(SavedCookie(original)))
        let restored = try #require(decoded.cookie)
        #expect(restored.name == "session")
        #expect(restored.value == "abc")
        #expect(restored.domain == ".upwork.com")
        #expect(restored.isSecure)
        #expect(restored.isHTTPOnly)
        #expect(restored.sameSitePolicy == .sameSiteLax)
        #expect(restored.isSessionOnly)
    }
}

@MainActor
struct SessionCookieStoreTests {
    private let file = FileManager.default.temporaryDirectory.appendingPathComponent("cookies-\(UUID().uuidString).json")

    private func cookie(_ name: String) throws -> HTTPCookie {
        try #require(HTTPCookie(properties: [.name: name, .value: "v", .domain: "example.com", .path: "/"]))
    }

    @Test func keepsTheFileAfterLoading() throws {
        let store = SessionCookieStore(fileURL: file)
        defer { try? FileManager.default.removeItem(at: file) }
        store.write([try cookie("a")])
        #expect(store.load().map(\.name) == ["a"])
        #expect(store.load().map(\.name) == ["a"])
    }

    @Test func writesPrivatelyAndClearedCookiesRemoveTheFile() throws {
        let store = SessionCookieStore(fileURL: file)
        defer { try? FileManager.default.removeItem(at: file) }
        store.write([try cookie("a")])
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
        store.write([])
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(store.load().isEmpty)
    }

    @Test func overwritesWithTheLatestCookies() throws {
        let store = SessionCookieStore(fileURL: file)
        defer { try? FileManager.default.removeItem(at: file) }
        store.write([try cookie("a")])
        store.write([try cookie("b")])
        #expect(store.load().map(\.name) == ["b"])
    }
}
