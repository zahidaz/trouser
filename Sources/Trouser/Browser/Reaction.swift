import Foundation

@MainActor
enum Reaction {
    static let scrollLimit: Duration = .milliseconds(250)
    static let scrollAnswer: Duration = .milliseconds(100)
    static let scrollPoll: Duration = .milliseconds(5)
    static let poll: Duration = .milliseconds(30)

    static func read<Value>(
        _ read: () async throws -> Value,
        within limit: Duration,
        every interval: Duration = poll,
        until reacted: (Value) -> Bool
    ) async throws -> Value {
        let deadline = ContinuousClock.now + limit
        while true {
            try await Task.sleep(for: min(interval, deadline - .now))
            let value = try await read()
            guard !reacted(value), ContinuousClock.now < deadline else { return value }
        }
    }
}
