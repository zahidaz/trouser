import Foundation

extension Command {
    init(arguments: [String]) throws {
        var arguments = arguments
        var profile: String?
        if arguments.first == "-p" || arguments.first == "--profile" {
            guard arguments.count >= 2 else { throw CommandError.usage }
            profile = arguments[1]
            arguments.removeFirst(2)
        }
        guard let name = arguments.first else { throw CommandError.usage }
        let rest = Array(arguments.dropFirst())
        switch name {
        case "status":
            guard rest.isEmpty, profile == nil else { throw CommandError.usage }
            self = .status
        case "background":
            guard profile == nil, rest.count == 1, let state = ["on": true, "off": false][rest[0]] else {
                throw CommandError.usage
            }
            self = .background(state)
        case "downloads":
            guard rest.isEmpty else { throw CommandError.usage }
            self = .downloads(profile: profile)
        case "rules":
            guard rest.isEmpty else { throw CommandError.usage }
            self = .rules(profile: profile)
        case "network":
            let flags = Set(rest)
            guard flags.count == rest.count, flags.isSubset(of: ["--json", "--hosts"]) else { throw CommandError.usage }
            self = .network(profile: profile, json: flags.contains("--json"), hosts: flags.contains("--hosts"))
        case "privacy":
            guard rest.isEmpty || rest == ["--json"] else { throw CommandError.usage }
            self = .privacy(profile: profile, json: !rest.isEmpty)
        case "profile" where rest.first == "delete":
            guard rest.count == 2, profile == nil else { throw CommandError.usage }
            self = .deleteProfile(rest[1])
        case "profile":
            guard rest.isEmpty else { throw CommandError.usage }
            self = .profile(profile: profile)
        case "open":
            guard rest.count <= 1 else { throw CommandError.usage }
            self = .open(profile: profile, url: try rest.first.map(Self.url))
        case "watch":
            self = .watch(profile: profile, try WatchOptions(arguments: rest))
        case "screenshot" where rest.first == "--live":
            self = .live(profile: profile, every: try LiveScreenshot.interval(arguments: Array(rest.dropFirst())))
        case "wait":
            let (condition, timeout) = try WaitCondition.parse(rest)
            self = .wait(profile: profile, condition, timeout: timeout)
        case "expect":
            self = .expect(profile: profile, try Expectation(arguments: rest))
        case "path":
            guard !rest.isEmpty else { throw CommandError.usage }
            self = .path(profile: profile, rest.joined(separator: " "))
        case "run":
            let steps = try RunScript.steps(rest).map { try Command(arguments: $0).defaulting(profile: profile) }
            guard !steps.isEmpty else { throw CommandError.usage }
            if steps.contains(where: \.isCompound) {
                throw CommandError.invalid("run steps cannot be run, watch, screenshot --live or profile delete commands")
            }
            self = .run(steps)
        default:
            let (options, arguments) = ActionOptions.parse(rest)
            let action = try PageAction(name: name, arguments: arguments)
            guard options == ActionOptions() || action.changesPage else {
                throw CommandError.invalid("--quiet applies to tap, set, show, click, drag, scroll, type, key, go and tab")
            }
            self = .page(profile: profile, action: action, options: options)
        }
    }

    static func url(_ text: String) throws -> URL {
        guard let url = URL(userInput: text) else { throw CommandError.invalid("“\(text)” is not an http or https URL") }
        return url
    }

    private var isCompound: Bool {
        switch self {
        case .run, .watch, .live, .deleteProfile: true
        default: false
        }
    }

    private func defaulting(profile fallback: String?) -> Command {
        guard profile == nil, let fallback else { return self }
        switch self {
        case .open(_, let url): return .open(profile: fallback, url: url)
        case .page(_, let action, let options): return .page(profile: fallback, action: action, options: options)
        case .downloads: return .downloads(profile: fallback)
        case .rules: return .rules(profile: fallback)
        case .network(_, let json, let hosts): return .network(profile: fallback, json: json, hosts: hosts)
        case .privacy(_, let json): return .privacy(profile: fallback, json: json)
        case .profile: return .profile(profile: fallback)
        case .watch(_, let options): return .watch(profile: fallback, options)
        case .live(_, let every): return .live(profile: fallback, every: every)
        case .wait(_, let condition, let timeout): return .wait(profile: fallback, condition, timeout: timeout)
        case .path(_, let query): return .path(profile: fallback, query)
        case .expect(_, let expectation): return .expect(profile: fallback, expectation)
        case .status, .background, .run, .deleteProfile: return self
        }
    }
}

extension ActionOptions {
    static func parse(_ arguments: [String]) -> (ActionOptions, [String]) {
        var options = ActionOptions()
        var arguments = arguments
        while let flag = arguments.last {
            switch flag {
            case "--quiet": options.quiet = true
            default: return (options, arguments)
            }
            arguments.removeLast()
        }
        return (options, arguments)
    }
}

extension Navigation {
    init(argument: String) throws {
        switch argument {
        case "back": self = .back
        case "forward": self = .forward
        case "reload": self = .reload
        default: self = .url(try Command.url(argument))
        }
    }
}

extension TabAction {
    init(arguments: [String]) throws {
        switch arguments.first {
        case "new" where arguments.count <= 2: self = .new(try arguments.dropFirst().first.map(Command.url))
        case "close" where arguments.count == 1: self = .close
        case let index? where arguments.count == 1:
            guard let number = Int(index), number > 0 else { throw CommandError.invalid("invalid tab “\(index)”") }
            self = .select(number)
        default: throw CommandError.usage
        }
    }
}

extension PageAction {
    init(name: String, arguments: some Collection<String>) throws {
        let arguments = Array(arguments)
        switch name {
        case "screenshot":
            guard arguments.isEmpty || arguments == ["--full"] else { throw CommandError.usage }
            self = .screenshot(fullPage: !arguments.isEmpty)
        case "source":
            guard arguments.isEmpty || arguments == ["--all"] else { throw CommandError.usage }
            self = .source(all: !arguments.isEmpty)
        case "page":
            let flags = Set(arguments)
            let all = flags.contains("--all")
            guard flags.count == arguments.count, flags.isSubset(of: all ? ["--all", "--json", "--ocr"] : ["--json"]) else {
                throw CommandError.usage
            }
            self = all ? .state(json: flags.contains("--json"), recognizing: flags.contains("--ocr")) : .brief(json: flags.contains("--json"))
        case "query":
            self = .query(try ModelQuery(arguments: arguments))
        case "tap":
            let target = try Self.target(arguments)
            self = ElementCommand.id(target).map { .act(ElementCommand(id: $0, operation: .tap)) } ?? .intent(Intent(target: target))
        case "set":
            guard arguments.count >= 2 else { throw CommandError.usage }
            let target = try Self.target([arguments[0]])
            let text = arguments.dropFirst().joined(separator: " ")
            self = ElementCommand.id(target).map { .act(ElementCommand(id: $0, operation: .set(text))) } ?? .intent(Intent(target: target, value: text))
        case "show":
            let target = try Self.target(arguments)
            self = ElementCommand.id(target).map { .act(ElementCommand(id: $0, operation: .show)) } ?? .find(target)
        case "click":
            try Self.expect(arguments, 2...3)
            let count = try arguments.count == 3 ? Self.integer(arguments[2], in: 1...3) : 1
            self = .click(try Self.point(arguments), count: count)
        case "drag":
            try Self.expect(arguments, 4...4)
            self = .drag(from: try Self.point(arguments), to: try Self.point(Array(arguments.dropFirst(2))))
        case "scroll":
            try Self.expect(arguments, 4...4)
            self = .scroll(try Self.point(arguments), dx: try Self.number(arguments[2]), dy: try Self.number(arguments[3]))
        case "type":
            guard !arguments.isEmpty else { throw CommandError.usage }
            self = .type(arguments.joined(separator: " "))
        case "key":
            try Self.expect(arguments, 1...1)
            self = .key(try KeyCombo(parsing: arguments[0]))
        case "go":
            try Self.expect(arguments, 1...1)
            self = .navigate(try Navigation(argument: arguments[0]))
        case "tab":
            self = .tab(try TabAction(arguments: arguments))
        default:
            throw CommandError.usage
        }
    }

    private static func target(_ arguments: [String]) throws -> String {
        let target = arguments.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { throw CommandError.usage }
        return target
    }

    private static func expect(_ arguments: [String], _ range: ClosedRange<Int>) throws {
        guard range.contains(arguments.count) else { throw CommandError.usage }
    }

    private static func point(_ arguments: [String]) throws -> CGPoint {
        CGPoint(x: try number(arguments[0]), y: try number(arguments[1]))
    }

    private static func number(_ text: String) throws -> Double {
        guard let value = Double(text) else { throw CommandError.invalid("expected a number, got “\(text)”") }
        return value
    }

    private static func integer(_ text: String, in range: ClosedRange<Int>) throws -> Int {
        guard let value = Int(text), range.contains(value) else {
            throw CommandError.invalid("expected \(range.lowerBound)–\(range.upperBound), got “\(text)”")
        }
        return value
    }
}
