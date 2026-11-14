import Foundation

enum WaitCondition: Equatable {
    case load
    case idle
    case url(String)
    case text(String)
    case event(String)

    struct State {
        var isLoading: Bool
        var url: URL?
        var idle: SettleStep
        var elements: [PageElement] = []
        var events: [Event] = []
    }

    static let defaultTimeout: Duration = .seconds(30)

    init(arguments: [String]) throws {
        guard let name = arguments.first else { throw CommandError.usage }
        let value = arguments.dropFirst().joined(separator: " ")
        switch name {
        case "load" where value.isEmpty: self = .load
        case "idle" where value.isEmpty: self = .idle
        case "url" where !value.isEmpty: self = .url(value)
        case "text" where !value.isEmpty: self = .text(value)
        case "event" where arguments.count == 2:
            try WatchOptions.validate(value)
            self = .event(value)
        default: throw CommandError.usage
        }
    }

    static func parse(_ arguments: [String]) throws -> (WaitCondition, timeout: Duration) {
        guard let flag = arguments.firstIndex(of: "--timeout") else {
            return (try WaitCondition(arguments: arguments), defaultTimeout)
        }
        guard flag == arguments.count - 2, let seconds = Double(arguments[flag + 1]), seconds > 0 else {
            throw CommandError.invalid("--timeout expects a number of seconds as the last argument")
        }
        return (try WaitCondition(arguments: Array(arguments[..<flag])), .milliseconds(Int(seconds * 1000)))
    }

    var readsPage: Bool {
        if case .text = self { true } else { false }
    }

    func recheck(after state: State) -> Duration {
        switch self {
        case .text: .milliseconds(250)
        case _ where state.isLoading: .milliseconds(100)
        case .idle:
            if case .wait(let duration) = state.idle { duration } else { .zero }
        case .load, .url, .event: .seconds(1)
        }
    }

    func holds(in state: State) -> Bool {
        switch self {
        case .load: !state.isLoading && state.url != nil
        case .idle: !state.isLoading && [.finish(.settled), .finish(.unchanged)].contains(state.idle)
        case .url(let text): state.url?.absoluteString.localizedCaseInsensitiveContains(text) ?? false
        case .text(let text): !PageMap.match(text, in: state.elements).isEmpty
        case .event(let pattern): state.events.contains { $0.type.matches(pattern) }
        }
    }

    var summary: String {
        switch self {
        case .load: "page load"
        case .idle: "idle page"
        case .url(let text): "URL containing “\(text)”"
        case .text(let text): "text “\(text)”"
        case .event(let pattern): "event \(pattern)"
        }
    }
}
