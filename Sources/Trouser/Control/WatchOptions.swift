import Foundation

struct WatchOptions: Equatable {
    var json = false
    var types: [String] = []
    var count: Int?
    var until: String?
    var since: Int?
}

extension WatchOptions {
    init(arguments: [String]) throws {
        var arguments = arguments[...]
        while let flag = arguments.popFirst() {
            if flag == "--json" {
                json = true
                continue
            }
            guard let value = arguments.popFirst() else { throw CommandError.usage }
            switch flag {
            case "--types":
                types = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                guard !types.isEmpty else { throw CommandError.usage }
                try types.forEach(Self.validate)
            case "--count":
                guard let number = Int(value), number > 0 else { throw CommandError.invalid("expected a positive count, got “\(value)”") }
                count = number
            case "--until":
                try Self.validate(value)
                until = value
            case "--since":
                guard let number = Int(value), number >= 0 else { throw CommandError.invalid("expected an event number, got “\(value)”") }
                since = number
            default:
                throw CommandError.usage
            }
        }
    }

    func includes(_ event: Event) -> Bool {
        types.isEmpty || types.contains { event.type.matches($0) } || stops(at: event)
    }

    func stops(at event: Event) -> Bool {
        until.map { event.type.matches($0) } ?? false
    }

    func render(_ event: Event) -> String {
        json ? event.json : event.line
    }

    static func validate(_ pattern: String) throws {
        guard EventType.isKnown(pattern) else {
            throw CommandError.invalid("unknown event type “\(pattern)”; use one of: \(EventType.categories.joined(separator: ", ")) or a full type such as navigation.finished")
        }
    }
}
