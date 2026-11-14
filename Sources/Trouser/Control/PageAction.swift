import Foundation

enum Navigation: Equatable {
    case url(URL)
    case back, forward, reload
}

enum TabAction: Equatable {
    case new(URL?)
    case close
    case select(Int)
}

enum PageAction: Equatable {
    case brief(json: Bool)
    case state(json: Bool, recognizing: Bool)
    case query(ModelQuery)
    case act(ElementCommand)
    case intent(Intent)
    case find(String)
    case screenshot(fullPage: Bool)
    case source(all: Bool)
    case click(CGPoint, count: Int)
    case drag(from: CGPoint, to: CGPoint)
    case scroll(CGPoint, dx: Double, dy: Double)
    case type(String)
    case key(KeyCombo)
    case navigate(Navigation)
    case tab(TabAction)

    var kind: ActionKind {
        switch self {
        case .brief, .state, .query, .screenshot, .source: .view
        case .act(let command): command.kind
        case .intent(let intent): intent.value == nil ? .pointer : .keyboard
        case .click, .drag: .pointer
        case .scroll, .find: .scroll
        case .type, .key: .keyboard
        case .navigate, .tab: .navigate
        }
    }

    var point: CGPoint? {
        switch self {
        case .click(let point, _), .scroll(let point, _, _), .drag(let point, _): point
        case .act(let command): command.target.flatMap { $0.visible ? $0.center : nil }
        default: nil
        }
    }

    var destination: URL? {
        switch self {
        case .navigate(.url(let url)), .tab(.new(let url?)): url
        default: nil
        }
    }

    var leavesTab: Bool {
        if case .tab = self { true } else { false }
    }

    var changesPage: Bool {
        switch self {
        case .brief, .state, .query, .find, .screenshot, .source: false
        default: true
        }
    }

    var typedLength: Int {
        switch self {
        case .type(let text): text.count
        case .act(let command): command.typedLength
        default: 0
        }
    }

    var targetLabel: String? {
        switch self {
        case .act(let command): command.targetLabel
        default: nil
        }
    }

    var pressedLabel: String? {
        switch self {
        case .act(let command) where command.operation == .tap: command.target?.label
        default: nil
        }
    }

    var focusedElement: String? {
        if case .act(let command) = self, command.focuses { command.id } else { nil }
    }

    var summary: String {
        switch self {
        case .screenshot(let fullPage): fullPage ? "full-page screenshot" : "screenshot"
        case .source(let all): all ? "save all page resources" : "save page source"
        case .brief: "read page"
        case .state: "read whole page"
        case .query: "query page model"
        case .act(let command): command.summary
        case .intent(let intent): intent.summary
        case .find(let text): "show “\(text)”"
        case .click(let point, let count):
            "\(["click", "double-click", "triple-click"][count - 1]) at \(Self.describe(point))"
        case .drag(let start, let end): "drag from \(Self.describe(start)) to \(Self.describe(end))"
        case .scroll(let point, let dx, let dy): "scroll (\(Int(dx)), \(Int(dy))) at \(Self.describe(point))"
        case .type(let text): "type “\(text.count > 40 ? text.prefix(40) + "…" : text)”"
        case .key(let combo): "press \(combo.name)"
        case .navigate(.url(let url)): "go to \(url.absoluteString)"
        case .navigate(.back): "go back"
        case .navigate(.forward): "go forward"
        case .navigate(.reload): "reload"
        case .tab(.new(let url)): url.map { "new tab \($0.absoluteString)" } ?? "new tab"
        case .tab(.close): "close tab"
        case .tab(.select(let index)): "switch to tab \(index)"
        }
    }

    private static func describe(_ point: CGPoint) -> String {
        "(\(Int(point.x)), \(Int(point.y)))"
    }
}
