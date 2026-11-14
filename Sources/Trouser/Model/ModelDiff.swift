import Foundation

struct ModelDiff: Equatable {
    enum Field: Equatable {
        case label, value, placeholder, states, url, visible, frame
    }

    struct Change: Equatable {
        let before: ModelElement
        let after: ModelElement
        let fields: [Field]

        var movedOnly: Bool {
            fields == [.frame]
        }
    }

    let page: [String]
    let added: [ModelElement]
    let removed: [ModelElement]
    let changed: [Change]

    init(from old: PageModel, to new: PageModel) {
        let before = Dictionary(old.elements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let after = Set(new.elements.map(\.id))
        page = Self.pageChanges(old.page, new.page) + (old.focus == new.focus ? [] : ["focus \(old.focus ?? "none") → \(new.focus ?? "none")"])
        added = new.elements.filter { before[$0.id] == nil }
        removed = old.elements.filter { !after.contains($0.id) }
        changed = new.elements.compactMap { element in
            guard let previous = before[element.id] else { return nil }
            let fields = Self.fields(previous, element)
            return fields.isEmpty ? nil : Change(before: previous, after: element, fields: fields)
        }
    }

    var isEmpty: Bool {
        page.isEmpty && added.isEmpty && removed.isEmpty && changed.isEmpty
    }

    var description: String {
        isEmpty ? "no changes" : lines.joined(separator: "\n")
    }

    var lines: [String] {
        let moved = changed.filter(\.movedOnly).count
        var lines = page.map { "page  \($0)" }
        lines += added.map { "+ \($0.description)" }
        lines += removed.map { "- \($0.description)" }
        lines += changed.filter { !$0.movedOnly }.flatMap { change in
            ["~ \(change.after.description)", "    \(change.fields.filter { $0 != .frame }.map { Self.detail($0, change) }.joined(separator: ", "))"]
        }
        if moved > 0 {
            lines.append("\(moved) element\(moved == 1 ? "" : "s") moved")
        }
        return lines
    }

    private static func pageChanges(_ old: PageInfo, _ new: PageInfo) -> [String] {
        var changes: [String] = []
        if old.url != new.url { changes.append("url \(old.url?.absoluteString ?? "none") → \(new.url?.absoluteString ?? "none")") }
        if old.title != new.title { changes.append("title “\(old.title)” → “\(new.title)”") }
        if old.loading != new.loading { changes.append(new.loading ? "started loading" : "finished loading") }
        if old.secure != new.secure { changes.append(new.secure ? "became secure" : "became not secure") }
        if old.viewport != new.viewport { changes.append("viewport \(Int(new.viewport.width))×\(Int(new.viewport.height))") }
        return changes
    }

    private static func fields(_ old: ModelElement, _ new: ModelElement) -> [Field] {
        var fields: [Field] = []
        if old.label != new.label { fields.append(.label) }
        if old.value != new.value { fields.append(.value) }
        if old.placeholder != new.placeholder { fields.append(.placeholder) }
        if old.states != new.states { fields.append(.states) }
        if old.url != new.url { fields.append(.url) }
        if old.visible != new.visible { fields.append(.visible) }
        if old.visible, new.visible, let from = old.center, let to = new.center,
           abs(from.x - to.x) > movementTolerance || abs(from.y - to.y) > movementTolerance {
            fields.append(.frame)
        }
        return fields
    }

    private static func detail(_ field: Field, _ change: Change) -> String {
        let old = change.before
        let new = change.after
        switch field {
        case .label: return "label “\(old.label)” → “\(new.label)”"
        case .value: return "value \(quoted(old.value)) → \(quoted(new.value))"
        case .placeholder: return "placeholder \(quoted(old.placeholder)) → \(quoted(new.placeholder))"
        case .states: return "states \(list(old.states)) → \(list(new.states))"
        case .url: return "url \(old.url?.absoluteString ?? "none") → \(new.url?.absoluteString ?? "none")"
        case .visible, .frame: return new.visible ? "now visible at \(new.position)" : "no longer visible"
        }
    }

    private static func quoted(_ text: String?) -> String {
        text.map { "“\($0)”" } ?? "empty"
    }

    private static func list(_ states: [ElementState]) -> String {
        states.isEmpty ? "none" : states.map(\.rawValue).joined(separator: " ")
    }

    private static let movementTolerance: CGFloat = 2
}
