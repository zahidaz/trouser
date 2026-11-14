import Foundation
import Testing
@testable import Trouser

struct ProxyRequestTests {
    @Test func waitsForTheWholeHead() throws {
        #expect(try ProxyRequest.parse(Data("CONNECT example.com:443 HTTP/1.1\r\nHost: example.com".utf8)) == nil)
    }

    @Test func parsesConnect() throws {
        let head = "CONNECT Example.com:443 HTTP/1.1\r\nHost: example.com:443\r\nProxy-Authorization: Basic abc\r\n\r\n"
        let request = try #require(try ProxyRequest.parse(Data((head + "early").utf8)))
        #expect(request.kind == .tunnel)
        #expect(request.host == "example.com")
        #expect(request.port == 443)
        #expect(request.authorization == "Basic abc")
        #expect(request.headerLength == head.utf8.count)
        #expect(request.upstreamHead.isEmpty)
    }

    @Test func parsesIPv6Authority() throws {
        let request = try #require(try ProxyRequest.parse(Data("CONNECT [::1]:8443 HTTP/1.1\r\n\r\n".utf8)))
        #expect(request.host == "::1")
        #expect(request.port == 8443)
    }

    @Test func rewritesPlainHTTPToOriginForm() throws {
        let head = "GET http://example.com:8080/a/b?q=1 HTTP/1.1\r\nHost: example.com:8080\r\nProxy-Connection: keep-alive\r\nProxy-Authorization: Basic abc\r\nAccept: */*\r\n\r\n"
        let request = try #require(try ProxyRequest.parse(Data(head.utf8)))
        #expect(request.kind == .http)
        #expect(request.port == 8080)
        let upstream = String(decoding: request.upstreamHead, as: UTF8.self)
        #expect(upstream == "GET /a/b?q=1 HTTP/1.1\r\nHost: example.com:8080\r\nAccept: */*\r\nConnection: close\r\n\r\n")
    }

    @Test func addsMissingHostHeader() throws {
        let request = try #require(try ProxyRequest.parse(Data("GET http://example.com HTTP/1.1\r\n\r\n".utf8)))
        #expect(request.port == 80)
        #expect(String(decoding: request.upstreamHead, as: UTF8.self) == "GET / HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\n\r\n")
    }

    @Test func rejectsBadRequests() {
        #expect(throws: ProxyRequestError.malformed) { try ProxyRequest.parse(Data("CONNECT example.com HTTP/1.1\r\n\r\n".utf8)) }
        #expect(throws: ProxyRequestError.malformed) { try ProxyRequest.parse(Data("HELLO\r\n\r\n".utf8)) }
        #expect(throws: ProxyRequestError.unsupported("https")) { try ProxyRequest.parse(Data("GET https://a.dev/ HTTP/1.1\r\n\r\n".utf8)) }
        #expect(throws: ProxyRequestError.tooLarge) { try ProxyRequest.parse(Data(repeating: 65, count: ProxyRequest.headLimit + 1)) }
    }
}
