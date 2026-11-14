import CryptoKit
import Foundation

struct ContentRule: Encodable, Equatable {
    struct Trigger: Encodable, Equatable {
        var urlFilter: String
        var resourceType: [String]?
        var loadType: [String]?

        enum CodingKeys: String, CodingKey {
            case urlFilter = "url-filter"
            case resourceType = "resource-type"
            case loadType = "load-type"
        }
    }

    struct Action: Encodable, Equatable {
        var type: String
        var selector: String?
    }

    var trigger: Trigger
    var action: Action

    static func block(_ trigger: Trigger) -> ContentRule {
        ContentRule(trigger: trigger, action: Action(type: "block"))
    }
}

enum ContentRules {
    static func rules(for settings: ProfileSettings) -> [ContentRule] {
        let trackers = settings.blockTrackers ? TrackerList.domains.map { domainRule($0, thirdPartyOnly: true) } : []
        let domains = settings.blockedDomains.compactMap(normalizedDomain).map { domainRule($0, thirdPartyOnly: false) }
        let images = settings.blockImages ? [ContentRule.block(.init(urlFilter: ".*", resourceType: ["image"]))] : []
        let fonts = settings.blockFonts ? [ContentRule.block(.init(urlFilter: ".*", resourceType: ["font"]))] : []
        let hidden = settings.hiddenSelectors
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { ContentRule(trigger: .init(urlFilter: ".*"), action: .init(type: "css-display-none", selector: $0)) }
        return trackers + domains + images + fonts + hidden
    }

    static func json(for settings: ProfileSettings) -> String? {
        let rules = rules(for: settings)
        guard !rules.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(rules)).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func identifier(for json: String) -> String {
        let digest = SHA256.hash(data: Data(json.utf8))
        return "trouser-" + digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    static func normalizedDomain(_ text: String) -> String? {
        var domain = HostRules.normalize(text)
        if domain.hasPrefix("*.") {
            domain.removeFirst(2)
        }
        return domain.wholeMatch(of: /[a-z0-9-]+(\.[a-z0-9-]+)*/) == nil ? nil : domain
    }

    private static func domainRule(_ domain: String, thirdPartyOnly: Bool) -> ContentRule {
        let escaped = domain.replacingOccurrences(of: ".", with: "\\.")
        return .block(.init(urlFilter: "^[^:]+://+([^:/]+\\.)?\(escaped)[:/]", loadType: thirdPartyOnly ? ["third-party"] : nil))
    }
}
