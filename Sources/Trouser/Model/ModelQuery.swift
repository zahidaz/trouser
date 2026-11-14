import Foundation

struct ModelQuery: Equatable {
    var roles: Set<ElementRole> = []
    var states: Set<ElementState> = []
    var excludedStates: Set<ElementState> = []
    var ids: Set<String> = []
    var visible: Bool?
    var text: String?

    init(arguments: [String]) throws {
        var words: [String] = []
        for token in Self.tokens(arguments) {
            if token.quoted {
                words.append(token.text)
            } else if !apply(token.text.lowercased()) {
                words.append(token.text)
            }
        }
        text = words.isEmpty ? nil : words.joined(separator: " ")
        guard text != nil || !roles.isEmpty || !states.isEmpty || !excludedStates.isEmpty || !ids.isEmpty || visible != nil else {
            throw CommandError.usage
        }
    }

    func select(from elements: [ModelElement]) -> [ModelElement] {
        let filtered = elements.filter(matchesFilters)
        guard let needle = text?.matchKey else { return filtered }
        return filtered
            .enumerated()
            .compactMap { index, element in
                [element.label, element.value ?? ""]
                    .compactMap { TextMatch(needle, in: $0.matchKey) }
                    .min()
                    .map { (index: index, match: $0, element: element) }
            }
            .sorted { ($0.match, $0.index) < ($1.match, $1.index) }
            .map(\.element)
    }

    private func matchesFilters(_ element: ModelElement) -> Bool {
        (roles.isEmpty || roles.contains(element.role))
            && states.isSubset(of: element.states)
            && excludedStates.isDisjoint(with: element.states)
            && (ids.isEmpty || ids.contains(element.id))
            && (visible.map { $0 == element.visible } ?? true)
    }

    private mutating func apply(_ word: String) -> Bool {
        if let role = ElementRole(rawValue: word) ?? Self.roleAliases[word] {
            roles.insert(role)
        } else if let state = ElementState(rawValue: word) {
            states.insert(state)
        } else if word.hasPrefix("!"), let state = ElementState(rawValue: String(word.dropFirst())) {
            excludedStates.insert(state)
        } else if word == "enabled" {
            excludedStates.insert(.disabled)
        } else if word == "visible" || word == "hidden" {
            visible = word == "visible"
        } else if word.wholeMatch(of: /e[0-9]+/) != nil {
            ids.insert(word)
        } else {
            return false
        }
        return true
    }

    private static let roleAliases: [String: ElementRole] = [
        "input": .textbox, "field": .textbox, "combobox": .select, "img": .image, "toggle": .switch
    ]

    private static func tokens(_ arguments: [String]) -> [(text: String, quoted: Bool)] {
        arguments.flatMap { argument -> [(text: String, quoted: Bool)] in
            guard argument.contains(where: { quotes.contains($0) }) else {
                return argument.contains(where: \.isWhitespace) ? [(argument, true)] : [(argument, false)]
            }
            var tokens: [(text: String, quoted: Bool)] = []
            var current = ""
            var quoted = false
            func flush() {
                if !current.isEmpty { tokens.append((current, quoted)) }
                current = ""
            }
            for character in argument {
                if quotes.contains(character) {
                    flush()
                    quoted.toggle()
                } else if character.isWhitespace, !quoted {
                    flush()
                } else {
                    current.append(character)
                }
            }
            flush()
            return tokens
        }
    }

    private static let quotes: Set<Character> = ["\"", "“", "”"]
}
