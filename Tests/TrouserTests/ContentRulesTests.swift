import Foundation
import Testing
@testable import Trouser

struct ContentRulesTests {
    @Test func defaultSettingsProduceNoRules() {
        #expect(ContentRules.json(for: ProfileSettings()) == nil)
    }

    @Test func generatesExactJSON() {
        var settings = ProfileSettings()
        settings.blockImages = true
        settings.blockFonts = true
        settings.blockedDomains = ["Ads.Example.com", "*.cdn.test", "not a domain"]
        settings.hiddenSelectors = [".banner", "  "]
        let expected = #"[{"action":{"type":"block"},"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?ads\\.example\\.com[:/]"}},{"action":{"type":"block"},"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?cdn\\.test[:/]"}},{"action":{"type":"block"},"trigger":{"resource-type":["image"],"url-filter":".*"}},{"action":{"type":"block"},"trigger":{"resource-type":["font"],"url-filter":".*"}},{"action":{"selector":".banner","type":"css-display-none"},"trigger":{"url-filter":".*"}}]"#
        #expect(ContentRules.json(for: settings) == expected)
    }

    @Test func trackersBlockOnlyThirdPartyLoads() throws {
        var settings = ProfileSettings()
        settings.blockTrackers = true
        let rules = ContentRules.rules(for: settings)
        #expect(rules.count == TrackerList.domains.count)
        let first = try #require(rules.first)
        #expect(first.trigger.loadType == ["third-party"])
        #expect(first.trigger.urlFilter == #"^[^:]+://+([^:/]+\.)?2mdn\.net[:/]"#)
    }

    @Test func identifierFollowsTheRules() {
        let identifier = ContentRules.identifier(for: "[1]")
        #expect(identifier == ContentRules.identifier(for: "[1]"))
        #expect(identifier != ContentRules.identifier(for: "[2]"))
        #expect(identifier.hasPrefix("trouser-") && identifier.count == 32)
    }
}
