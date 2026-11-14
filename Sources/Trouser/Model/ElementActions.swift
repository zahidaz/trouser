import Foundation

@MainActor
struct ElementActions {
    let driver: PageDriver
    let models: PageModelStore

    func resolve(_ command: ElementCommand) async throws -> ElementCommand {
        let element = try await element(command.id)
        if command.focuses, !element.role.isFillable {
            throw ModelError.notFillable(element)
        }
        var resolved = command
        resolved.target = element
        return resolved
    }

    func perform(_ command: ElementCommand) async throws -> ContinuousClock.Instant {
        let element = try await revealed(try await element(command.id))
        guard let point = await models.pressPoint(for: element) else { throw ModelError.notPlaceable(element) }
        let pressed = ContinuousClock.now
        switch command.operation {
        case .show:
            break
        case .tap:
            try driver.perform(.click(point, count: 1))
        case .set(let text):
            try driver.perform(.click(point, count: 1))
            try await models.focusMoved(since: pressed, within: Self.focusLimit)
            try driver.perform(.key(try KeyCombo(parsing: "cmd+a")))
            try driver.perform(text.isEmpty ? .key(try KeyCombo(parsing: "backspace")) : .type(text))
        }
        return pressed
    }

    private func element(_ id: String) async throws -> ModelElement {
        try await models.search { model in
            guard let element = model.element(id) else { throw ModelError.unknownElement(id) }
            return element
        }
    }

    private func revealed(_ element: ModelElement) async throws -> ModelElement {
        guard !element.visible else { return element }
        guard !element.offscreen else { return try await scrolled(to: element) }
        if let standIn = Self.standIn(for: element, among: try await models.current().elements) {
            return standIn
        }
        do {
            _ = try await models.reveal(element.label)
        } catch DriverError.notFound {
            throw ModelError.notPlaceable(element)
        }
        models.invalidate()
        guard let revealed = try await models.current().element(element.id), revealed.visible else {
            throw ModelError.notPlaceable(element)
        }
        return revealed
    }

    private func scrolled(to element: ModelElement) async throws -> ModelElement {
        var current = element
        for _ in 0..<Self.scrollAttempts {
            guard let frame = current.frame else { break }
            let viewport = driver.webView.bounds
            let anchor = CGPoint(x: viewport.midX, y: viewport.midY)
            try driver.perform(.scroll(anchor, dx: frame.midX < 0 || frame.midX > viewport.width ? frame.midX - viewport.midX : 0, dy: frame.midY - viewport.height * 0.4))
            let read = try await Reaction.read({ try await rendered(element.id) }, within: Reaction.scrollLimit) { $0?.frame != frame }
            guard let moved = read else { break }
            if moved.visible { return moved }
            current = moved
        }
        throw ModelError.notPlaceable(element)
    }

    private func rendered(_ id: String) async throws -> ModelElement? {
        models.invalidate()
        return try await models.current().element(id)
    }

    static func standIn(for target: ModelElement, among elements: [ModelElement]) -> ModelElement? {
        let label = normalized(target.label)
        guard !label.isEmpty else { return nil }
        return elements
            .filter { $0.visible && $0.id != target.id }
            .map { ($0, normalized($0.label)) }
            .filter { $0.1.count >= Self.minimumStandInLength && label.hasPrefix($0.1) && !splitsNumber(label, after: $0.1) }
            .max { $0.1.count < $1.1.count }?
            .0
    }

    private static func splitsNumber(_ label: String, after prefix: String) -> Bool {
        guard let last = prefix.last, last.isNumber, label.count > prefix.count else { return false }
        return label[label.index(label.startIndex, offsetBy: prefix.count)].isNumber
    }

    private static func normalized(_ label: String) -> String {
        label.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "[]")))
    }

    private static let scrollAttempts = 4
    private static let focusLimit: Duration = .milliseconds(100)
    private static let minimumStandInLength = 2
}
