import Foundation

struct ElementCommand: Equatable {
    enum Operation: Equatable {
        case tap, show
        case set(String)
    }

    let id: String
    let operation: Operation
    var target: ModelElement?

    init(id: String, operation: Operation, target: ModelElement? = nil) {
        self.id = id
        self.operation = operation
        self.target = target
    }

    static func id(_ text: String) -> String? {
        let id = text.lowercased()
        return id.wholeMatch(of: /e[0-9]+/) == nil ? nil : id
    }

    var kind: ActionKind {
        switch operation {
        case .tap: .pointer
        case .set: .keyboard
        case .show: .scroll
        }
    }

    var summary: String {
        let name = target.map { "\(id) \($0.role.rawValue) “\($0.label)”" } ?? id
        switch operation {
        case .tap: return "tap \(name)"
        case .show: return "show \(name)"
        case .set(let text): return "set \(name) to “\(text.count > 40 ? text.prefix(40) + "…" : text)”"
        }
    }

    var targetLabel: String? {
        guard let target else { return nil }
        return target.label.isEmpty ? target.context : target.label
    }

    var typedLength: Int {
        if case .set(let text) = operation { text.count } else { 0 }
    }

    var focuses: Bool {
        if case .set = operation { true } else { false }
    }
}
