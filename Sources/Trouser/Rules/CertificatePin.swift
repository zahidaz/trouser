import Foundation

struct CertificateSummary: Equatable, Sendable {
    let issuerNames: [String]
    let spki: SPKIFingerprint
}

struct CertificatePin: Codable, Hashable, Identifiable, Sendable {
    var pattern: HostPattern
    var issuers: [String] = []
    var spkiSHA256: [SPKIFingerprint] = []

    var id: HostPattern { pattern }

    var isEmpty: Bool {
        issuers.isEmpty && spkiSHA256.isEmpty
    }

    var summary: String {
        let issuers = issuers.isEmpty ? [] : ["issuers: \(issuers.joined(separator: ", "))"]
        let keys = spkiSHA256.isEmpty ? [] : ["spki: \(spkiSHA256.map(\.description).joined(separator: ", "))"]
        return (issuers + keys).joined(separator: "; ")
    }

    func accepts(_ chain: [CertificateSummary]) -> Bool {
        guard let leaf = chain.first else { return false }
        let allowed = Set(issuers.map(Self.normalize))
        let issuerMatches = leaf.issuerNames.contains { allowed.contains(Self.normalize($0)) }
        let keyMatches = chain.contains { spkiSHA256.contains($0.spki) }
        return issuerMatches || keyMatches
    }

    private static func normalize(_ name: String) -> String {
        name.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
