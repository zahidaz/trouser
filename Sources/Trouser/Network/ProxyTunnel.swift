import Foundation
import Network
import os

struct ProxyTunnel: Sendable {
    let client: NWConnection
    let proxy: NetworkProxy
    let queue: DispatchQueue

    private static let chunk = 64 * 1024
    private static let connectTimeout = 20
    private static let waitingGrace: DispatchTimeInterval = .seconds(5)

    func start() {
        client.start(queue: queue)
        readHead(Data())
    }

    private func readHead(_ buffer: Data) {
        client.receive(minimumIncompleteLength: 1, maximumLength: Self.chunk) { data, _, isComplete, error in
            var buffer = buffer
            data.map { buffer.append($0) }
            do {
                if let request = try ProxyRequest.parse(buffer) {
                    route(request, leftover: Data(buffer.dropFirst(request.headerLength)))
                } else if isComplete || error != nil {
                    client.cancel()
                } else {
                    readHead(buffer)
                }
            } catch {
                reply("400 Bad Request")
            }
        }
    }

    private func route(_ request: ProxyRequest, leftover: Data) {
        guard proxy.accepts(request.authorization) else {
            reply("407 Proxy Authentication Required", headers: ["Proxy-Authenticate: Basic realm=\"Trouser\""])
            return
        }
        let (id, permitted) = proxy.open(request)
        guard permitted else {
            proxy.close(id, .blocked)
            reply("403 Forbidden")
            return
        }
        connect(request, id: id, leftover: leftover)
    }

    private func connect(_ request: ProxyRequest, id: Int, leftover: Data) {
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = Self.connectTimeout
        let upstream = NWConnection(
            host: NWEndpoint.Host(request.host),
            port: NWEndpoint.Port(rawValue: request.port) ?? .https,
            using: NWParameters(tls: nil, tcp: tcp)
        )
        let link = TunnelLink(id: id, proxy: proxy, client: client, upstream: upstream)
        upstream.stateUpdateHandler = { state in
            switch state {
            case .ready:
                guard link.begin() else { return }
                let opening = request.kind == .tunnel
                    ? (client: Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8), upstream: leftover)
                    : (client: Data(), upstream: request.upstreamHead + leftover)
                if !opening.client.isEmpty {
                    client.send(content: opening.client, completion: .idempotent)
                }
                if !opening.upstream.isEmpty {
                    proxy.transfer(id, up: opening.upstream.count)
                    upstream.send(content: opening.upstream, completion: .idempotent)
                }
                pipe(from: client, to: upstream, link: link, upstreamBound: true)
                pipe(from: upstream, to: client, link: link, upstreamBound: false)
            case .waiting(.dns(let error)):
                refuse(link, NWError.dns(error))
            case .waiting(let error):
                queue.asyncAfter(deadline: .now() + Self.waitingGrace) {
                    guard !link.isStarted else { return }
                    refuse(link, error)
                }
            case .failed(let error):
                refuse(link, error)
            default:
                break
            }
        }
        upstream.start(queue: queue)
    }

    private func refuse(_ link: TunnelLink, _ error: NWError) {
        guard link.fail(error.localizedDescription) else { return }
        reply("502 Bad Gateway")
    }

    private func pipe(from source: NWConnection, to destination: NWConnection, link: TunnelLink, upstreamBound: Bool) {
        source.receive(minimumIncompleteLength: 1, maximumLength: Self.chunk) { data, _, isComplete, error in
            let next: @Sendable (NWError?) -> Void = { sendError in
                if let failure = sendError ?? error {
                    link.fail(failure.localizedDescription)
                } else if isComplete {
                    destination.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .idempotent)
                    link.finishDirection()
                } else {
                    pipe(from: source, to: destination, link: link, upstreamBound: upstreamBound)
                }
            }
            guard let data, !data.isEmpty else {
                next(nil)
                return
            }
            proxy.transfer(link.id, up: upstreamBound ? data.count : 0, down: upstreamBound ? 0 : data.count)
            destination.send(content: data, completion: .contentProcessed(next))
        }
    }

    private func reply(_ status: String, headers: [String] = []) {
        let head = (["HTTP/1.1 \(status)"] + headers + ["Content-Length: 0", "Connection: close", "", ""]).joined(separator: "\r\n")
        client.send(content: Data(head.utf8), completion: .contentProcessed { [client] _ in client.cancel() })
    }
}

private final class TunnelLink: Sendable {
    private struct State {
        var started = false
        var openDirections = 2
        var closed = false
    }

    let id: Int
    private let proxy: NetworkProxy
    private let client: NWConnection
    private let upstream: NWConnection
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(id: Int, proxy: NetworkProxy, client: NWConnection, upstream: NWConnection) {
        self.id = id
        self.proxy = proxy
        self.client = client
        self.upstream = upstream
    }

    var isStarted: Bool {
        state.withLock { $0.started }
    }

    func begin() -> Bool {
        state.withLock { state in
            guard !state.started, !state.closed else { return false }
            state.started = true
            return true
        }
    }

    func finishDirection() {
        let done = state.withLock { state in
            state.openDirections -= 1
            return state.openDirections == 0
        }
        if done {
            close(.completed, error: nil)
        }
    }

    @discardableResult
    func fail(_ reason: String) -> Bool {
        let halfClosed = state.withLock { $0.openDirections < 2 }
        return close(halfClosed ? .completed : .failed, error: halfClosed ? nil : reason)
    }

    @discardableResult
    private func close(_ outcome: ConnectionRecord.Outcome, error: String?) -> Bool {
        let first = state.withLock { state in
            guard !state.closed else { return false }
            state.closed = true
            return true
        }
        guard first else { return false }
        proxy.close(id, outcome, error: error)
        upstream.cancel()
        if outcome != .failed || isStarted {
            client.cancel()
        }
        return true
    }
}
