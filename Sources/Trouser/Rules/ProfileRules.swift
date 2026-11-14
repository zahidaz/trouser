import Foundation

struct ProfileRules: Equatable, Sendable {
    static let version = 1

    static let defaultProtectedLabels = [
        "send*for review", "publish", "roll*out", "release", "delete", "remove",
        "pay", "buy", "purchase", "confirm payment", "submit order"
    ].compactMap(LabelPattern.init)

    var sites: [SiteRule] = []
    var protectedLabels = Self.defaultProtectedLabels
    var fence: [HostPattern] = []
    var pins: [CertificatePin] = []

    func sites(matching host: String?) -> [SiteRule] {
        sites.filter { $0.pattern.matches(host) }.sorted { $0.pattern.specificity > $1.pattern.specificity }
    }

    func protection(for label: String?) -> LabelPattern? {
        protectedLabels.first { $0.matches(label) }
    }

    func allowsNavigation(to url: URL) -> Bool {
        guard !fence.isEmpty, url.scheme != "about" else { return true }
        return fence.contains { $0.matches(url.host()) }
    }

    func fenceRefusal(for url: URL) -> String? {
        guard !allowsNavigation(to: url) else { return nil }
        let destination = url.host() ?? url.absoluteString
        return "\(destination) is outside the navigation fence (allowed: \(fence.map(\.text).joined(separator: ", ")))"
    }

    func pin(for host: String) -> CertificatePin? {
        pins.filter { $0.pattern.matches(host) }.max { $0.pattern.specificity < $1.pattern.specificity }
    }

    func mediaMode(_ devices: [MediaDevice], hosts: [String]) -> MediaMode {
        MediaMode.strictest(devices.flatMap { device in
            hosts.map { host in sites(matching: host).lazy.compactMap { $0.media[device] }.first ?? .deny }
        })
    }
}

extension ProfileRules: Codable {
    private enum CodingKeys: String, CodingKey {
        case version, sites, protectedLabels, fence, pins
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        guard version == Self.version else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: container, debugDescription: "unsupported version \(version)")
        }
        sites = try container.decodeIfPresent([SiteRule].self, forKey: .sites) ?? []
        protectedLabels = try container.decodeIfPresent([LabelPattern].self, forKey: .protectedLabels) ?? Self.defaultProtectedLabels
        fence = try container.decodeIfPresent([HostPattern].self, forKey: .fence) ?? []
        pins = try container.decodeIfPresent([CertificatePin].self, forKey: .pins) ?? []
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.version, forKey: .version)
        try container.encode(sites, forKey: .sites)
        try container.encode(protectedLabels, forKey: .protectedLabels)
        try container.encode(fence, forKey: .fence)
        try container.encode(pins, forKey: .pins)
    }
}

extension Array where Element: Identifiable {
    mutating func upsert(_ element: Element, replacing id: Element.ID?) {
        let index = id.flatMap { id in firstIndex { $0.id == id } }
        removeAll { $0.id == element.id || $0.id == id }
        insert(element, at: Swift.min(index ?? endIndex, endIndex))
    }
}
