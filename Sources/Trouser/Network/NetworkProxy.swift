import Foundation
import Network
import os

enum ProxyError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): "the network proxy could not start: \(reason)"
        }
    }
}

final class NetworkProxy: Sendable {
    private struct State {
        var log = ConnectionLog()
        var rules: HostRules
        var lastTraffic: ContinuousClock.Instant?
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "trouser.proxy")
    private let state: OSAllocatedUnfairLock<State>
    private let password: String
    private static let username = "trouser"

    init(rules: HostRules, password: String = UUID().uuidString) throws {
        self.password = password
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        do {
            listener = try NWListener(using: parameters)
        } catch {
            throw ProxyError.unavailable(error.localizedDescription)
        }
        state = OSAllocatedUnfairLock(initialState: State(rules: rules))
    }

    var log: ConnectionLog {
        state.withLock { $0.log }
    }

    var lastTraffic: ContinuousClock.Instant? {
        state.withLock { $0.lastTraffic }
    }

    func start() async throws -> ProxyConfiguration {
        let port = try await listen()
        let configuration = ProxyConfiguration(httpCONNECTProxy: .hostPort(host: .ipv4(.loopback), port: port))
        configuration.applyCredential(username: Self.username, password: password)
        return configuration
    }

    func stop() {
        listener.cancel()
    }

    func update(_ rules: HostRules) {
        state.withLock { $0.rules = rules }
    }

    func accepts(_ authorization: String?) -> Bool {
        authorization == "Basic " + Data("\(Self.username):\(password)".utf8).base64EncodedString()
    }

    func open(_ request: ProxyRequest) -> (id: Int, permitted: Bool) {
        state.withLock { state in
            let id = state.log.open(host: request.host, port: request.port, kind: request.kind)
            state.lastTraffic = .now
            return (id, state.rules.permits(request.host))
        }
    }

    func transfer(_ id: Int, up: Int = 0, down: Int = 0) {
        state.withLock { state in
            state.log.transfer(id, up: up, down: down)
            state.lastTraffic = .now
        }
    }

    func close(_ id: Int, _ outcome: ConnectionRecord.Outcome, error: String? = nil) {
        state.withLock { $0.log.close(id, outcome, error: error) }
    }

    private func listen() async throws -> NWEndpoint.Port {
        try await withCheckedThrowingContinuation { continuation in
            let pending = OSAllocatedUnfairLock<CheckedContinuation<NWEndpoint.Port, Error>?>(initialState: continuation)
            listener.stateUpdateHandler = { [listener] state in
                let result: Result<NWEndpoint.Port, Error>? = switch state {
                case .ready: listener.port.map { .success($0) } ?? .failure(ProxyError.unavailable("no port"))
                case .failed(let error): .failure(ProxyError.unavailable(error.localizedDescription))
                case .cancelled: .failure(ProxyError.unavailable("cancelled"))
                default: nil
                }
                guard let result else { return }
                pending.withLock { continuation in
                    continuation?.resume(with: result)
                    continuation = nil
                }
            }
            listener.newConnectionHandler = { [self, queue] connection in
                ProxyTunnel(client: connection, proxy: self, queue: queue).start()
            }
            listener.start(queue: queue)
        }
    }
}
