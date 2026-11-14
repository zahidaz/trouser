import CryptoKit
import Foundation

enum CertificateDER {
    static func summary(of der: Data) -> CertificateSummary? {
        let bytes = [UInt8](der)
        guard let certificate = element(in: bytes, at: 0), certificate.tag == sequence,
              let tbs = children(of: certificate, in: bytes).first, tbs.tag == sequence else { return nil }
        let ordered = Array(children(of: tbs, in: bytes).drop { $0.tag == explicitVersion })
        guard ordered.count > spkiIndex, ordered[issuerIndex].tag == sequence, ordered[spkiIndex].tag == sequence else { return nil }
        let spki = Data(bytes[ordered[spkiIndex].whole])
        return CertificateSummary(
            issuerNames: names(in: ordered[issuerIndex], bytes: bytes),
            spki: SPKIFingerprint(digest: Data(SHA256.hash(data: spki)))
        )
    }

    private struct Element {
        let tag: UInt8
        let content: Range<Int>
        let whole: Range<Int>
    }

    private static let sequence: UInt8 = 0x30
    private static let set: UInt8 = 0x31
    private static let objectIdentifier: UInt8 = 0x06
    private static let explicitVersion: UInt8 = 0xA0
    private static let issuerIndex = 2
    private static let spkiIndex = 5
    private static let organization: [UInt8] = [0x55, 0x04, 0x0A]
    private static let commonName: [UInt8] = [0x55, 0x04, 0x03]

    private static func names(in issuer: Element, bytes: [UInt8]) -> [String] {
        let attributes = children(of: issuer, in: bytes)
            .filter { $0.tag == set }
            .flatMap { children(of: $0, in: bytes) }
            .compactMap { attribute -> (oid: [UInt8], value: String)? in
                let parts = children(of: attribute, in: bytes)
                guard parts.count == 2, parts[0].tag == objectIdentifier,
                      let value = string(parts[1], bytes: bytes) else { return nil }
                return (Array(bytes[parts[0].content]), value)
            }
        return [organization, commonName].flatMap { oid in attributes.filter { $0.oid == oid }.map(\.value) }
    }

    private static func string(_ element: Element, bytes: [UInt8]) -> String? {
        let content = Data(bytes[element.content])
        switch element.tag {
        case 0x0C, 0x13, 0x16: return String(data: content, encoding: .utf8)
        case 0x14: return String(data: content, encoding: .isoLatin1)
        case 0x1E: return String(data: content, encoding: .utf16BigEndian)
        default: return nil
        }
    }

    private static func children(of parent: Element, in bytes: [UInt8]) -> [Element] {
        var result: [Element] = []
        var offset = parent.content.lowerBound
        while offset < parent.content.upperBound, let child = element(in: bytes, at: offset, limit: parent.content.upperBound) {
            result.append(child)
            offset = child.whole.upperBound
        }
        return result
    }

    private static func element(in bytes: [UInt8], at offset: Int, limit: Int? = nil) -> Element? {
        let limit = limit ?? bytes.count
        guard offset + 2 <= limit else { return nil }
        let tag = bytes[offset]
        var length = Int(bytes[offset + 1])
        var header = 2
        if length & 0x80 != 0 {
            let count = length & 0x7F
            guard (1...4).contains(count), offset + 2 + count <= limit else { return nil }
            length = bytes[(offset + 2)..<(offset + 2 + count)].reduce(0) { $0 << 8 | Int($1) }
            header += count
        }
        let end = offset + header + length
        guard end <= limit else { return nil }
        return Element(tag: tag, content: (offset + header)..<end, whole: offset..<end)
    }
}
