import Foundation

struct HostPattern: Hashable, Sendable, Identifiable, CustomStringConvertible {
    let text: String

    init?(_ raw: String) {
        let text = Self.normalize(raw)
        let suffix = text.hasPrefix("*.") ? String(text.dropFirst(2)) : text
        guard text == "*" || Self.isHost(suffix) else { return nil }
        self.text = text
    }

    var id: String { text }

    var description: String { text }

    var specificity: Int {
        if text == "*" { return 0 }
        return text.hasPrefix("*.") ? text.count : Self.exactBonus + text.count
    }

    func matches(_ candidate: String?) -> Bool {
        guard let candidate else { return false }
        let host = Self.normalize(candidate)
        guard !host.isEmpty else { return false }
        if text == "*" { return true }
        guard text.hasPrefix("*.") else { return host == text }
        let suffix = text.dropFirst(2)
        return host == suffix || host.hasSuffix("." + suffix)
    }

    private static let exactBonus = 1_000

    private static func normalize(_ host: String) -> String {
        var host = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while host.hasSuffix(".") {
            host.removeLast()
        }
        return host
    }

    private static func isHost(_ text: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-_.:")
        let labels = text.split(separator: ".", omittingEmptySubsequences: false)
        return !text.isEmpty
            && text.unicodeScalars.allSatisfy(allowed.contains)
            && labels.allSatisfy { !$0.isEmpty }
    }
}

extension HostPattern: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let pattern = HostPattern(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "invalid host pattern “\(raw)”")
        }
        self = pattern
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(text)
    }
}
