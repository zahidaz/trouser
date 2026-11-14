import Foundation

struct SiteAtlas: Codable, Equatable {
    struct Transition: Codable, Equatable {
        let from: PageSignature
        let label: String
        var to: PageSignature
        var used: Int
    }

    private(set) var transitions: [Transition] = []
    private var clock = 0

    static let capacity = 400

    mutating func record(from: PageSignature, label: String, to: PageSignature) {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard from != to, !label.isEmpty else { return }
        clock += 1
        let key = label.matchKey
        if let index = transitions.firstIndex(where: { $0.from == from && $0.label.matchKey == key }) {
            transitions[index].to = to
            transitions[index].used = clock
        } else {
            transitions.append(Transition(from: from, label: label, to: to, used: clock))
        }
        if transitions.count > Self.capacity, let stalest = transitions.indices.min(by: { transitions[$0].used < transitions[$1].used }) {
            transitions.remove(at: stalest)
        }
    }

    func destinations(from page: PageSignature?) -> [String: String] {
        guard let page else { return [:] }
        return Dictionary(
            transitions.filter { $0.from == page }.map { ($0.label.matchKey, $0.to.name) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func route(from start: PageSignature, to query: String) -> [Transition]? {
        let key = query.matchKey
        guard !key.isEmpty else { return nil }
        if start.matches(key) { return [] }
        var paths: [PageSignature: [Transition]] = [start: []]
        var frontier = [start]
        while !frontier.isEmpty {
            var next: [PageSignature] = []
            for page in frontier {
                for transition in transitions where transition.from == page && paths[transition.to] == nil {
                    let path = paths[page, default: []] + [transition]
                    if transition.to.matches(key) || transition.label.matchKey == key {
                        return path
                    }
                    paths[transition.to] = path
                    next.append(transition.to)
                }
            }
            frontier = next
        }
        return nil
    }
}
