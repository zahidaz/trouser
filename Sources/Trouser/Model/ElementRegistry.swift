import Foundation

final class ElementRegistry {
    private var ids: [String: String] = [:]
    private var next = 1

    func assign(_ elements: [ModelElement]) -> [ModelElement] {
        var occurrences: [String: Int] = [:]
        var used = Set<String>()
        return elements.map { element in
            let base = "\(element.role.rawValue)|\(element.name.matchKey)"
            let occurrence = occurrences[base, default: 0]
            occurrences[base] = occurrence + 1
            let keys = [element.identity.map { "node|\($0)" }, "\(base)|\(occurrence)"].compactMap { $0 }
            let id = keys.lazy.compactMap { self.ids[$0] }.first { !used.contains($0) } ?? makeID()
            keys.forEach { ids[$0] = id }
            used.insert(id)
            var identified = element
            identified.id = id
            return identified
        }
    }

    private func makeID() -> String {
        let id = "e\(next)"
        next += 1
        return id
    }
}
