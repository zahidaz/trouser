import Foundation

struct Intent: Equatable {
    let target: String
    let value: String?

    init(target: String, value: String? = nil) {
        self.target = target
        self.value = value
    }

    var summary: String {
        value.map { "set “\(target)” to “\($0)”" } ?? "tap “\(target)”"
    }
}

struct IntentMatch: Equatable {
    let element: ModelElement
    let score: Double
    let reasons: [String]

    var description: String {
        let placed = element.label.isEmpty || reasons.contains { $0.hasPrefix("in ") }
        let place = placed ? "" : element.context.map { " in “\($0)”" } ?? ""
        return "\(element.id) \(element.role.rawValue) “\(element.name)”\(place) — \(reasons.joined(separator: ", "))"
    }
}

enum IntentRanker {
    static let decisiveGap = 2.0
    static let minimumScore = 4.0
    static let shownCandidates = 3

    static func choose(_ intent: Intent, in model: PageModel, destinations: [String: String] = [:]) throws -> ModelElement {
        let ranked = rank(intent, in: model, destinations: destinations)
        guard let best = ranked.first, best.score >= minimumScore else { throw ModelError.noIntentMatch(intent.target) }
        let contenders = ranked.filter { best.score - $0.score < decisiveGap }
        guard contenders.count > 1 else { return best.element }
        let onScreen = contenders.filter(\.element.visible)
        let twins = contenders.allSatisfy { $0.element.role == best.element.role && $0.element.name.matchKey == best.element.name.matchKey }
        guard twins, onScreen.count == 1 else {
            throw ModelError.ambiguous(intent.target, Array(ranked.prefix(shownCandidates)))
        }
        return onScreen[0].element
    }

    static func rank(_ intent: Intent, in model: PageModel, destinations: [String: String] = [:]) -> [IntentMatch] {
        let words = intent.target.matchKey.split(separator: " ").map(String.init)
        let described = words.filter { roleWords[$0] == nil }
        let roles = described.isEmpty ? [] : Set(words.compactMap { roleWords[$0] })
        let needle = (described.isEmpty ? words : described).joined(separator: " ")
        guard !needle.isEmpty else { return [] }
        return model.elements.enumerated()
            .filter { _, element in isCandidate(element, setting: intent.value != nil) }
            .compactMap { index, element in
                score(element, needle: needle, roles: roles, destination: destinations[element.name.matchKey])
                    .map { (index: index, match: $0) }
            }
            .sorted { ($0.match.score, -$0.index) > ($1.match.score, -$1.index) }
            .map(\.match)
    }

    private static func isCandidate(_ element: ModelElement, setting: Bool) -> Bool {
        guard element.source == .dom || element.role == .link else { return false }
        return setting ? element.role.isFillable : element.role.isActionable
    }

    private static func score(_ element: ModelElement, needle: String, roles: Set<ElementRole>, destination: String?) -> IntentMatch? {
        var score = 0.0
        var reasons: [String] = []
        func add(_ points: Double, _ reason: String) {
            score += points
            reasons.append(reason)
        }
        let label = element.label.matchKey
        switch TextMatch(needle, in: label) {
        case .exact: add(10, "label is “\(element.label)”")
        case .prefix: add(7, "label starts with “\(needle)”")
        case .contains: add(5, "label contains “\(needle)”")
        case nil:
            let overlap = wordOverlap(needle, label)
            if overlap > 0 { add(4 * overlap, "label shares words with “\(needle)”") }
        }
        if let placeholder = element.placeholder?.matchKey, placeholder.contains(needle) {
            add(3, "placeholder “\(element.placeholder ?? "")”")
        }
        if let context = element.context?.matchKey, context.contains(needle) {
            add(element.label.isEmpty ? 6 : 2, "in “\(element.context ?? "")”")
        }
        if let destination, destination.matchKey.contains(needle) {
            add(5, "leads to “\(destination)”")
        }
        if let path = element.url?.path().lowercased(), path.contains(needle.replacingOccurrences(of: " ", with: "-")) || path.contains(needle.replacingOccurrences(of: " ", with: "")) {
            add(2, "link to \(element.url?.path() ?? "")")
        }
        guard score > 0 else { return nil }
        if roles.contains(element.role) {
            add(2, "is a \(element.role.rawValue)")
        }
        if element.visible { score += 0.5 }
        if element.states.contains(.disabled) { add(-3, "disabled") }
        return IntentMatch(element: element, score: score, reasons: reasons)
    }

    private static func wordOverlap(_ needle: String, _ label: String) -> Double {
        let wanted = Set(needle.split(separator: " "))
        let present = Set(label.split(separator: " "))
        guard !wanted.isEmpty else { return 0 }
        return Double(wanted.intersection(present).count) / Double(wanted.count)
    }

    private static let roleWords: [String: ElementRole] = [
        "button": .button, "link": .link, "tab": .tab, "field": .textbox, "textbox": .textbox, "box": .textbox,
        "checkbox": .checkbox, "radio": .radio, "menu": .menuitem, "option": .option, "switch": .switch, "toggle": .switch
    ]
}
