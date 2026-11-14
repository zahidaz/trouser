import Foundation
import Testing
@testable import Trouser

struct HostPatternTests {
    @Test func matchesExactHosts() throws {
        let pattern = try #require(HostPattern("Shop.Example.com."))
        #expect(pattern.text == "shop.example.com")
        #expect(pattern.matches("shop.example.com"))
        #expect(pattern.matches("SHOP.example.com."))
        #expect(!pattern.matches("example.com"))
        #expect(!pattern.matches("evilshop.example.com"))
        #expect(!pattern.matches(nil))
    }

    @Test func wildcardsMatchApexAndSubdomains() throws {
        let pattern = try #require(HostPattern("*.example.com"))
        #expect(pattern.matches("example.com"))
        #expect(pattern.matches("shop.example.com"))
        #expect(pattern.matches("a.b.example.com"))
        #expect(!pattern.matches("notexample.com"))
        #expect(!pattern.matches("example.com.evil.dev"))
        #expect(try #require(HostPattern("*")).matches("anything.dev"))
    }

    @Test func rejectsMalformedPatterns() {
        for text in ["", " ", "*.*", "shop.*.com", "exa mple.com", "a..b", "https://example.com", "*example.com", "example.com/x"] {
            #expect(HostPattern(text) == nil, "\(text)")
        }
    }

    @Test func ranksSpecificity() throws {
        let exact = try #require(HostPattern("shop.example.com"))
        let wildcard = try #require(HostPattern("*.example.com"))
        let broad = try #require(HostPattern("*.com"))
        let any = try #require(HostPattern("*"))
        #expect(exact.specificity > wildcard.specificity)
        #expect(wildcard.specificity > broad.specificity)
        #expect(broad.specificity > any.specificity)
    }
}

struct LabelPatternTests {
    @Test func matchesSubstringsIgnoringCase() throws {
        let pattern = try #require(LabelPattern("Send  for review"))
        #expect(pattern.matches("SEND FOR REVIEW"))
        #expect(pattern.matches("Send for\nreview now"))
        #expect(!pattern.matches("Send"))
        #expect(!pattern.matches(nil))
    }

    @Test func matchesWildcardsAnywhereInLabel() throws {
        let pattern = try #require(LabelPattern("send*for review"))
        #expect(pattern.matches("Send 3 changes for review"))
        #expect(pattern.matches("Send for review"))
        #expect(!pattern.matches("Review and send"))
        #expect(try #require(LabelPattern("roll?out")).matches("Start roll-out"))
        #expect(!(try #require(LabelPattern("roll?out")).matches("rollout")))
        #expect(try #require(LabelPattern("pay $*.00")).matches("Pay $5.00 now"))
    }

    @Test func rejectsEmptyPatterns() {
        #expect(LabelPattern("  ") == nil)
        #expect(LabelPattern("*") == nil)
        #expect(LabelPattern("?*") == nil)
    }

    @Test func defaultsCoverReleaseAndPaymentButtons() {
        let rules = ProfileRules()
        for label in ["Send for review", "Send 3 changes for review", "Publish app", "Start roll-out", "Start rollout to Production", "Roll out", "Delete draft", "Buy now", "Confirm payment", "Submit order"] {
            #expect(rules.protection(for: label) != nil, "\(label)")
        }
        #expect(rules.protection(for: "Save draft") == nil)
    }
}

struct DecisionTests {
    private func rules() throws -> ProfileRules {
        var rules = ProfileRules()
        rules.sites = [
            SiteRule(pattern: try #require(HostPattern("*.example.com")), actions: [.pointer: .allow, .keyboard: .allow, .download: .block]),
            SiteRule(pattern: try #require(HostPattern("shop.example.com")), actions: [.keyboard: .ask])
        ]
        return rules
    }

    @Test func fallsBackToGlobalMode() throws {
        let decision = try rules().decision(for: .pointer, context: ActionContext(host: "other.example"), global: .ask, paused: false)
        #expect(decision == Decision(mode: .ask, source: .global))
    }

    @Test func mostSpecificSiteSettingTheKindWins() throws {
        let rules = try rules()
        let shop = ActionContext(host: "shop.example.com")
        #expect(rules.decision(for: .keyboard, context: shop, global: .block, paused: false).mode == .ask)
        let pointer = rules.decision(for: .pointer, context: shop, global: .block, paused: false)
        #expect(pointer == Decision(mode: .allow, source: .site(try #require(HostPattern("*.example.com")))))
        #expect(rules.decision(for: .scroll, context: shop, global: .allow, paused: false).source == .global)
    }

    @Test func protectedLabelsForceAsk() throws {
        let decision = try rules().decision(
            for: .pointer,
            context: ActionContext(host: "shop.example.com", label: "Send 3 changes for review"),
            global: .allow,
            paused: false
        )
        #expect(decision == Decision(mode: .ask, source: .protected(try #require(LabelPattern("send*for review")))))
    }

    @Test func protectionNeverLoosensBlockAndOnlyCoversClicksAndKeys() throws {
        var rules = try rules()
        rules.sites.append(SiteRule(pattern: try #require(HostPattern("console.dev")), actions: [.pointer: .block]))
        let blocked = rules.decision(for: .pointer, context: ActionContext(host: "console.dev", label: "Delete"), global: .allow, paused: false)
        #expect(blocked.mode == .block)
        let navigation = rules.decision(for: .navigate, context: ActionContext(host: "console.dev", label: "Delete"), global: .allow, paused: false)
        #expect(navigation == Decision(mode: .allow, source: .global))
    }

    @Test func pauseBeatsEverything() throws {
        let rules = try rules()
        for kind in ActionKind.allCases {
            let decision = rules.decision(for: kind, context: ActionContext(host: "shop.example.com", label: "Publish"), global: .allow, paused: true)
            #expect(decision == Decision(mode: .block, source: .paused))
        }
    }
}

struct FenceTests {
    @Test func emptyFenceAllowsEverything() throws {
        #expect(ProfileRules().allowsNavigation(to: try #require(URL(string: "https://evil.dev"))))
    }

    @Test func fenceAllowsOnlyListedHosts() throws {
        var rules = ProfileRules()
        rules.fence = [try #require(HostPattern("*.example.com")), try #require(HostPattern("127.0.0.1"))]
        #expect(rules.allowsNavigation(to: try #require(URL(string: "https://shop.example.com/admin"))))
        #expect(rules.allowsNavigation(to: try #require(URL(string: "http://127.0.0.1:8765/form.html"))))
        #expect(rules.allowsNavigation(to: try #require(URL(string: "about:blank"))))
        #expect(!rules.allowsNavigation(to: try #require(URL(string: "https://example.com.evil.dev"))))
        #expect(!rules.allowsNavigation(to: try #require(URL(string: "data:text/html,hi"))))
        #expect(rules.fenceRefusal(for: try #require(URL(string: "https://evil.dev/x"))) == "evil.dev is outside the navigation fence (allowed: *.example.com, 127.0.0.1)")
        #expect(rules.fenceRefusal(for: try #require(URL(string: "https://mail.example.com"))) == nil)
    }
}

struct PinTests {
    static let certificate = Data(base64Encoded: """
    MIIBwTCCAWegAwIBAgIUXxbEUM8m0TOH0e0JwZ5yRpgfLcgwCgYIKoZIzj0EAwIwNjEYMBYGA1UECgwPRW5jbGF2ZSBUZXN0IENBMRowGAYDVQQDDBFF\
    bmNsYXZlIFRlc3QgUm9vdDAeFw0yNjExMDUwMTMwMTRaFw0zNjExMDIwMTMwMTRaMDYxGDAWBgNVBAoMD0VuY2xhdmUgVGVzdCBDQTEaMBgGA1UEAwwR\
    RW5jbGF2ZSBUZXN0IFJvb3QwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAARzvlr6yY50SFN3kf2udHPmaDXtWy9hDoJOMxJOVbTS6BRP2DGrjqN6R/rR\
    77ne4McC+vvUDewcGGDpR9wUYZMSo1MwUTAdBgNVHQ4EFgQUQ8KqH5VXM2eqE62sYgdRuKsVWdIwHwYDVR0jBBgwFoAUQ8KqH5VXM2eqE62sYgdRuKsV\
    WdIwDwYDVR0TAQH/BAUwAwEB/zAKBggqhkjOPQQDAgNIADBFAiBRlu4ucsVGpK7SMvzBUxVZb22fR0HxFBRawy9ue+yfiQIhAPCgBydHBA26H0KeQrPn\
    wbzvD4FVDHKNR1Huc0DLC6Ub
    """)!

    static let spki = "qaKnj+K9J0X5QniIEn2Acb3ohfaZ85i3a8RNaFgjLio="

    @Test func readsIssuerAndSPKIFromDER() throws {
        let summary = try #require(CertificateDER.summary(of: Self.certificate))
        #expect(summary.issuerNames == ["Enclave Test CA", "Enclave Test Root"])
        #expect(summary.spki.description == Self.spki)
    }

    @Test func rejectsGarbage() {
        #expect(CertificateDER.summary(of: Data([0x30, 0x82, 0xFF])) == nil)
        #expect(CertificateDER.summary(of: Data()) == nil)
    }

    @Test func parsesFingerprintFormats() throws {
        let base64 = try #require(SPKIFingerprint(Self.spki))
        let hex = base64.digest.map { String(format: "%02X", $0) }.joined(separator: ":")
        #expect(SPKIFingerprint("sha256/\(Self.spki)") == base64)
        #expect(SPKIFingerprint(hex) == base64)
        #expect(SPKIFingerprint("abc") == nil)
        #expect(SPKIFingerprint(Data(repeating: 1, count: 20).base64EncodedString()) == nil)
    }

    @Test func pinAcceptsMatchingIssuerOrKey() throws {
        let chain = [try #require(CertificateDER.summary(of: Self.certificate))]
        let host = try #require(HostPattern("*.example.com"))
        #expect(CertificatePin(pattern: host, issuers: ["enclave test ca"]).accepts(chain))
        #expect(CertificatePin(pattern: host, issuers: ["Enclave Test Root"]).accepts(chain))
        #expect(CertificatePin(pattern: host, spkiSHA256: [try #require(SPKIFingerprint(Self.spki))]).accepts(chain))
        #expect(!CertificatePin(pattern: host, issuers: ["Let's Encrypt"]).accepts(chain))
        #expect(!CertificatePin(pattern: host, spkiSHA256: [SPKIFingerprint(digest: Data(repeating: 0, count: 32))]).accepts(chain))
        #expect(!CertificatePin(pattern: host, issuers: ["Enclave Test CA"]).accepts([]))
    }

    @Test func picksMostSpecificPin() throws {
        var rules = ProfileRules()
        rules.pins = [
            CertificatePin(pattern: try #require(HostPattern("*.example.com")), issuers: ["Example Trust Services"]),
            CertificatePin(pattern: try #require(HostPattern("shop.example.com")), issuers: ["Other"])
        ]
        #expect(rules.pin(for: "shop.example.com")?.issuers == ["Other"])
        #expect(rules.pin(for: "mail.example.com")?.issuers == ["Example Trust Services"])
        #expect(rules.pin(for: "other.example") == nil)
    }
}

struct MediaRuleTests {
    @Test func deniesByDefaultAndCombinesStrictly() throws {
        var rules = ProfileRules()
        #expect(rules.mediaMode([.camera], hosts: ["meet.example.com"]) == .deny)
        rules.sites = [
            SiteRule(pattern: try #require(HostPattern("*.example.com")), media: [.camera: .allow, .microphone: .ask]),
            SiteRule(pattern: try #require(HostPattern("meet.example.com")), media: [.camera: .ask])
        ]
        #expect(rules.mediaMode([.camera], hosts: ["mail.example.com"]) == .allow)
        #expect(rules.mediaMode([.camera], hosts: ["meet.example.com"]) == .ask)
        #expect(rules.mediaMode([.camera, .microphone], hosts: ["mail.example.com"]) == .ask)
        #expect(rules.mediaMode([.camera], hosts: ["mail.example.com", "ads.example"]) == .deny)
        #expect(rules.mediaMode([], hosts: ["mail.example.com"]) == .deny)
    }
}

@MainActor
struct RuleStoreTests {
    private let file = FileManager.default.temporaryDirectory.appendingPathComponent("trouser-rules-\(UUID().uuidString).json")

    @Test func startsWithDefaults() {
        let store = RuleStore(fileURL: file)
        #expect(store.rules == ProfileRules())
        #expect(store.isReadable)
    }

    @Test func roundTripsEverything() throws {
        var rules = ProfileRules()
        rules.sites = [SiteRule(pattern: try #require(HostPattern("*.example.com")), actions: [.pointer: .allow], media: [.camera: .ask])]
        rules.protectedLabels = [try #require(LabelPattern("ship it"))]
        rules.fence = [try #require(HostPattern("shop.example.com"))]
        rules.pins = [CertificatePin(pattern: try #require(HostPattern("shop.example.com")), issuers: ["Example Trust Services"], spkiSHA256: [try #require(SPKIFingerprint(PinTests.spki))])]
        RuleStore(fileURL: file).update { $0 = rules }

        let reloaded = RuleStore(fileURL: file)
        #expect(reloaded.rules == rules)
        let json = try #require(String(data: Data(contentsOf: file), encoding: .utf8))
        #expect(json.contains("\"version\" : 1"))
        #expect(json.contains("\"pointer\" : \"allow\""))
        #expect(json.contains("\"camera\" : \"ask\""))
    }

    @Test func missingKeysUseDefaults() throws {
        try Data(#"{"version": 1, "fence": ["*.example.com"]}"#.utf8).write(to: file)
        let store = RuleStore(fileURL: file)
        #expect(store.isReadable)
        #expect(store.rules.protectedLabels == ProfileRules.defaultProtectedLabels)
        #expect(store.rules.fence.map(\.text) == ["*.example.com"])
    }

    @Test func unreadableFileBlocksAutomation() async throws {
        try Data(#"{"version": 1, "fence": ["not a host"]}"#.utf8).write(to: file)
        let store = RuleStore(fileURL: file)
        #expect(!store.isReadable)
        let supervisor = Supervisor(policy: Policy(defaults: UserDefaults(suiteName: "trouser.tests.\(UUID().uuidString)")!), rules: store, events: EventBus(profile: "test"))
        #expect(supervisor.decision(for: .view) == Decision(mode: .block, source: .unreadableRules))
        store.reset()
        #expect(store.isReadable)
        #expect(supervisor.decision(for: .view).mode == .allow)
    }

    @Test func rejectsFutureVersions() throws {
        try Data(#"{"version": 2}"#.utf8).write(to: file)
        #expect(!RuleStore(fileURL: file).isReadable)
    }
}

struct RulesReportTests {
    @Test func describesEffectiveRules() throws {
        var rules = ProfileRules()
        rules.sites = [SiteRule(pattern: try #require(HostPattern("*.example.com")), actions: [.pointer: .allow], media: [.camera: .ask])]
        rules.fence = [try #require(HostPattern("*.example.com"))]
        let report = RulesReport(
            profile: "play",
            paused: false,
            global: [:],
            rules: rules,
            loadError: nil,
            host: "shop.example.com"
        ).text
        #expect(report.contains("rules for profile “play”"))
        #expect(report.contains("effective on shop.example.com"))
        #expect(report.contains("pointer   allow  site *.example.com"))
        #expect(report.contains("camera    ask"))
        #expect(report.contains("send*for review, publish"))
        #expect(report.contains("none: system trust only"))
    }
}
