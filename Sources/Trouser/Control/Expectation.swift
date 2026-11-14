import Foundation

enum Expectation: Equatable {
    case page(WaitCondition)
    case noChange

    init(arguments: [String]) throws {
        switch arguments.first {
        case "no-change" where arguments.count == 1: self = .noChange
        case "text", "url": self = .page(try WaitCondition(arguments: arguments))
        default: throw CommandError.usage
        }
    }

    @MainActor
    func check(in session: ProfileSession) async -> Response {
        switch self {
        case .page(let condition):
            return await PageWaiter(session: session, condition: condition, timeout: .zero).check()
        case .noChange:
            switch session.lastChange {
            case false?: return .success("no change: as expected")
            case true?: return .failure("expected no change, but the last action changed the page")
            case nil: return .failure("expected no change, but no action has been compared yet; run an action without --quiet first")
            }
        }
    }
}
