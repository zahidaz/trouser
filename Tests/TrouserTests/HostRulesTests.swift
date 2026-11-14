import Testing
@testable import Trouser

struct HostRulesTests {
    @Test func emptyRulesPermitEverything() {
        #expect(HostRules().permits("example.com"))
    }

    @Test func matchesHostsAndSubdomains() {
        #expect(HostRules.matches("example.com", pattern: "example.com"))
        #expect(HostRules.matches("a.b.example.com", pattern: "Example.COM."))
        #expect(!HostRules.matches("badexample.com", pattern: "example.com"))
        #expect(HostRules.matches("cdn.example.com", pattern: "*.example.com"))
        #expect(!HostRules.matches("example.com", pattern: "*.example.com"))
        #expect(HostRules.matches("[::1]", pattern: "::1"))
        #expect(!HostRules.matches("example.com", pattern: " "))
    }

    @Test func blockWinsOverAllow() {
        let rules = HostRules(allowed: ["example.com"], blocked: ["ads.example.com"])
        #expect(rules.permits("www.example.com"))
        #expect(!rules.permits("ads.example.com"))
        #expect(!rules.permits("x.ads.example.com"))
        #expect(!rules.permits("other.org"))
    }
}
