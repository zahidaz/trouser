import Foundation
import Testing
@testable import Trouser

struct URLInputTests {
    @Test func keepsExplicitURLs() {
        #expect(URL(userInput: "http://localhost:8080/a") == URL(string: "http://localhost:8080/a"))
    }

    @Test func addsHTTPSToHosts() {
        #expect(URL(userInput: " example.com/path ") == URL(string: "https://example.com/path"))
    }

    @Test func rejectsNonWebSchemes() {
        #expect(URL(userInput: "javascript:alert(1)") == nil)
        #expect(URL(userInput: "file:///etc/passwd") == nil)
        #expect(URL(userInput: "data:text/html,<script>x</script>") == nil)
        #expect(URL(userInput: "localhost:8080") == URL(string: "https://localhost:8080"))
    }

    @Test func searchesEverythingElse() {
        #expect(URL(userInput: "swift concurrency")?.absoluteString == "https://duckduckgo.com/?q=swift%20concurrency")
        #expect(URL(userInput: "trouser")?.host() == "duckduckgo.com")
        #expect(URL(userInput: "   ") == nil)
    }
}
