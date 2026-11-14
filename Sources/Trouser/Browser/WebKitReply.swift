import Foundation

@MainActor
final class WebKitReply<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Error>?

    private init() {}

    static func value(within limit: Duration, _ request: (@escaping (Result<Value, Error>) -> Void) -> Void) async throws -> Value {
        let reply = WebKitReply()
        let timer = Task { @MainActor in
            try await Task.sleep(for: limit)
            reply.resume(.failure(DriverError.unanswered(limit)))
        }
        defer { timer.cancel() }
        return try await withCheckedThrowingContinuation { continuation in
            reply.continuation = continuation
            request { reply.resume($0) }
        }
    }

    private func resume(_ result: Result<Value, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}
