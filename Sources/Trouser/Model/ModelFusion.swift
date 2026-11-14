import Foundation

struct ModelFusion {
    private let texts: [PageElement]
    private let keys: [String]
    private let controlLabels: Set<String>
    private var claimed = Set<Int>()
    private var partial: [Int: [Range<Int>]] = [:]

    static func elements(controls: [DOMControl], texts: [PageElement], recognized: [PageElement] = []) -> [ModelElement] {
        var fusion = ModelFusion(texts: texts, controls: controls)
        let placed = controls.map { fusion.place($0) }
        let remaining = texts.indices.filter { !fusion.claimed.contains($0) }.flatMap(fusion.leftovers)
        return placed + remaining + unrecognized(recognized, known: placed.compactMap(\.frame) + texts.map(\.frame))
    }

    static func unrecognized(_ recognized: [PageElement], known: [CGRect]) -> [ModelElement] {
        recognized.filter { line in
            !known.contains { overlap(line.frame, $0) }
        }
        .map { ModelElement(role: .text, label: $0.text, frame: $0.frame, source: .ocr) }
    }

    static func readingOrder(_ elements: [ModelElement]) -> [ModelElement] {
        let placed = elements.filter(\.visible).sorted { lhs, rhs in
            let left = lhs.frame ?? .zero
            let right = rhs.frame ?? .zero
            return (left.minY.rounded(), left.minX) < (right.minY.rounded(), right.minX)
        }
        return placed + elements.filter { !$0.visible }
    }

    private init(texts: [PageElement], controls: [DOMControl]) {
        self.texts = texts
        keys = texts.map(\.text.matchKey)
        controlLabels = Set(controls.map(\.label.matchKey))
    }

    private mutating func place(_ control: DOMControl) -> ModelElement {
        var element = ModelElement(
            role: control.role,
            label: control.label,
            value: control.value,
            placeholder: control.placeholder,
            states: control.states,
            url: control.url,
            context: control.context,
            source: .dom
        )
        guard !control.role.isContainer else { return element }
        guard control.role.showsValue else {
            element.frame = control.drawsLabel ? claim(control.label, as: control.role == .link ? .inline : .apart) : nil
            return element
        }
        if let label = claim(control.label, as: .exact) {
            element.frame = label
            if !control.secret, control.placeholder?.matchKey != control.label.matchKey, let field = valueChunk(after: label) {
                claimed.insert(field)
                element.frame = texts[field].frame
                element.value = texts[field].text.matchKey == control.placeholder?.matchKey ? nil : texts[field].text
            }
        } else {
            for shown in [control.placeholder, control.value].compactMap({ $0 }) where element.frame == nil {
                element.frame = claim(shown, as: .exact)
            }
        }
        if element.frame == nil {
            element.frame = claim(control.label, as: .apart)
        }
        return element
    }

    private mutating func claim(_ text: String, as placement: Placement) -> CGRect? {
        let needle = text.matchKey
        let best = texts.indices
            .filter { !claimed.contains($0) }
            .compactMap { index in
                TextMatch.find(needle, in: keys[index], excluding: partial[index] ?? [], wholeWords: true).map { (index: index, match: $0.match, range: $0.range) }
            }
            .filter { $0.match == .exact || allows(placement, $0.range, in: $0.index) }
            .min { ($0.match, $0.index) < ($1.match, $1.index) }
        guard let best else { return nil }
        guard best.match != .exact else {
            claimed.insert(best.index)
            return texts[best.index].frame
        }
        partial[best.index, default: []].append(best.range)
        return slice(best.index, best.range)
    }

    private func allows(_ placement: Placement, _ range: Range<Int>, in index: Int) -> Bool {
        switch placement {
        case .exact: false
        case .apart: TextMatch.standsApart(range, in: keys[index], beside: controlLabels)
        case .inline: true
        }
    }

    private func leftovers(_ index: Int) -> [ModelElement] {
        let chunk = texts[index]
        let text = Array(chunk.text.split(whereSeparator: \.isWhitespace).joined(separator: " "))
        let taken = partial[index] ?? []
        guard !taken.isEmpty, text.count == keys[index].count else {
            return [ModelElement(role: chunk.link == nil ? .text : .link, label: chunk.text, frame: chunk.frame, url: chunk.link, source: .text)]
        }
        var segments: [Range<Int>] = []
        var start: Int?
        for offset in 0...text.count {
            let free = offset < text.count && !taken.contains { $0.contains(offset) }
            if free, start == nil {
                start = offset
            } else if !free, let begin = start {
                segments.append(begin..<offset)
                start = nil
            }
        }
        return segments.compactMap { range in
            let label = String(text[range]).trimmingCharacters(in: .whitespaces)
            guard label.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
            return ModelElement(role: .text, label: label, frame: slice(index, range), source: .text)
        }
    }

    private func slice(_ index: Int, _ range: Range<Int>) -> CGRect {
        let frame = texts[index].frame
        let total = CGFloat(max(keys[index].count, 1))
        return CGRect(
            x: frame.minX + frame.width * CGFloat(range.lowerBound) / total,
            y: frame.minY,
            width: frame.width * CGFloat(range.count) / total,
            height: frame.height
        )
    }

    private func valueChunk(after label: CGRect) -> Int? {
        let reach = max(label.height * Self.valueReach, Self.minimumValueGap)
        return texts.indices
            .filter { index in
                !claimed.contains(index) && texts[index].link == nil && !controlLabels.contains(keys[index])
            }
            .compactMap { index -> (index: Int, distance: CGFloat)? in
                let frame = texts[index].frame
                let sameLine = abs(frame.midY - label.midY) < label.height * 0.6
                if sameLine, frame.minX >= label.maxX, frame.minX - label.maxX <= Self.maximumSideGap {
                    return (index, frame.minX - label.maxX)
                }
                let gap = frame.minY - label.maxY
                guard frame.midY > label.maxY, gap <= reach, abs(frame.minX - label.minX) <= max(label.width, Self.minimumIndent) else {
                    return nil
                }
                return (index, max(gap, 0) + abs(frame.minX - label.minX) * 0.25)
            }
            .filter { candidate in !controlLabels.contains { keys[candidate.index].hasPrefix($0 + " ") } }
            .min { $0.distance < $1.distance }?
            .index
    }

    private static func overlap(_ line: CGRect, _ other: CGRect) -> Bool {
        let shared = line.intersection(other)
        return !shared.isNull && shared.width * shared.height >= line.width * line.height * 0.3
    }

    private enum Placement {
        case exact, apart, inline
    }

    private static let valueReach: CGFloat = 2.5
    private static let minimumValueGap: CGFloat = 36
    private static let minimumIndent: CGFloat = 60
    private static let maximumSideGap: CGFloat = 400
}
