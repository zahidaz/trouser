import Foundation

extension String {
    var matchKey: String {
        lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    var numberless: String {
        reduce(into: "") { result, character in
            guard character.isNumber else { return result.append(character) }
            if result.last != "#" { result.append("#") }
        }
    }

    var withoutPrivateUse: String {
        String(unicodeScalars.filter { !(0xE000...0xF8FF).contains($0.value) })
    }
}

enum TextMatch: Int, Comparable {
    case exact, prefix, contains

    static func < (lhs: TextMatch, rhs: TextMatch) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    init?(_ needle: String, in text: String) {
        guard let found = Self.find(needle, in: text) else { return nil }
        self = found.match
    }

    static func find(
        _ needle: String,
        in text: String,
        excluding taken: [Range<Int>] = [],
        wholeWords: Bool = false
    ) -> (match: TextMatch, range: Range<Int>)? {
        guard !needle.isEmpty else { return nil }
        let length = needle.count
        if taken.isEmpty, text == needle {
            return (.exact, 0..<length)
        }
        var start = text.startIndex
        while let found = text.range(of: needle, range: start..<text.endIndex) {
            let offset = text.distance(from: text.startIndex, to: found.lowerBound)
            let range = offset..<(offset + length)
            if !taken.contains(where: { $0.overlaps(range) }), !wholeWords || isWhole(found, in: text) {
                if offset == 0 { return (.prefix, range) }
                guard length >= minimumContainedLength else { return nil }
                return (.contains, range)
            }
            start = text.index(after: found.lowerBound)
        }
        return nil
    }

    static func standsApart(_ range: Range<Int>, in text: String, beside labels: Set<String>) -> Bool {
        let characters = Array(text)
        let before = String(characters[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        let after = String(characters[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        let opensApart = separates(before.last) || labels.contains { before.hasSuffix($0) && separates(before.dropLast($0.count).last) }
        return opensApart && (separates(after.first) || labels.contains { after.hasPrefix($0) && separates(after.dropFirst($0.count).first) })
    }

    private static func separates(_ neighbour: Character?) -> Bool {
        guard let neighbour else { return true }
        return !neighbour.isNumber && !(neighbour.isLetter && neighbour.isCased)
    }

    private static func isWhole(_ found: Range<String.Index>, in text: String) -> Bool {
        let before = found.lowerBound > text.startIndex ? text[text.index(before: found.lowerBound)] : nil
        let after = found.upperBound < text.endIndex ? text[found.upperBound] : nil
        return !continues(text[found.lowerBound], before) && !continues(text[text.index(before: found.upperBound)], after)
    }

    private static func continues(_ edge: Character, _ neighbour: Character?) -> Bool {
        guard let neighbour else { return false }
        return (edge.isNumber && neighbour.isNumber) || (edge.isLetter && edge.isCased && neighbour.isLetter && neighbour.isCased)
    }

    private static let minimumContainedLength = 3
}
