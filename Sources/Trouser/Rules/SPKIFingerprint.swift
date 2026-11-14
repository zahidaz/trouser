import Foundation

struct SPKIFingerprint: Hashable, Sendable, CustomStringConvertible {
    let digest: Data

    init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix(Self.prefix) {
            text.removeFirst(Self.prefix.count)
        }
        guard let digest = Self.hex(text) ?? Data(base64Encoded: text), digest.count == Self.length else { return nil }
        self.digest = digest
    }

    init(digest: Data) {
        self.digest = digest
    }

    var description: String { digest.base64EncodedString() }

    private static let prefix = "sha256/"
    private static let length = 32

    private static func hex(_ text: String) -> Data? {
        let digits = Array(text.replacingOccurrences(of: ":", with: "").lowercased())
        guard digits.count == length * 2, digits.allSatisfy(\.isHexDigit) else { return nil }
        return Data(stride(from: 0, to: digits.count, by: 2).compactMap { UInt8(String(digits[$0...$0 + 1]), radix: 16) })
    }
}

extension SPKIFingerprint: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let fingerprint = SPKIFingerprint(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "invalid SHA-256 fingerprint “\(raw)”")
        }
        self = fingerprint
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
