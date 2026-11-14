import Foundation

struct LabelPattern: Hashable, Sendable, Identifiable, CustomStringConvertible {
    let text: String

    init?(_ raw: String) {
        let text = Self.normalize(raw)
        guard !text.isEmpty, text.contains(where: { $0 != "*" && $0 != "?" }) else { return nil }
        self.text = text
    }

    var id: String { text }

    var description: String { text }

    var isWildcard: Bool {
        text.contains("*") || text.contains("?")
    }

    func matches(_ candidate: String?) -> Bool {
        guard let candidate else { return false }
        let label = Self.normalize(candidate)
        guard !label.isEmpty else { return false }
        return isWildcard ? Self.glob(Array("*\(text)*"), Array(label)) : label.contains(text)
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func glob(_ pattern: [Character], _ text: [Character]) -> Bool {
        var p = 0
        var t = 0
        var star: Int?
        var resume = 0
        while t < text.count {
            if p < pattern.count, pattern[p] == "?" || pattern[p] == text[t] {
                p += 1
                t += 1
            } else if p < pattern.count, pattern[p] == "*" {
                star = p
                resume = t
                p += 1
            } else if let star {
                p = star + 1
                resume += 1
                t = resume
            } else {
                return false
            }
        }
        while p < pattern.count, pattern[p] == "*" {
            p += 1
        }
        return p == pattern.count
    }
}

extension LabelPattern: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let pattern = LabelPattern(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "invalid label pattern “\(raw)”")
        }
        self = pattern
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(text)
    }
}
