import TrouserBridge
import Foundation
import WebKit

@MainActor
final class PreciseLink {
    private(set) var status = PreciseStatus.connecting
    private(set) var live: PreciseSnapshot?
    private(set) var lastFocus: ContinuousClock.Instant?
    var emit: (EventType, [String: String]) -> Void = { _, _ in }
    private var channel: TrouserBundleChannel?
    private let viewport: () -> CGSize

    private static let snapshotTimeout: TimeInterval = 2
    private static let hitTestTimeout: TimeInterval = 0.5

    init(webView: WKWebView) {
        viewport = { [weak webView] in webView?.bounds.size ?? .zero }
        channel = TrouserBundleChannel(webView: webView) { [weak self] json in
            self?.receive(json)
        }
    }

    func snapshot() async -> PreciseSnapshot? {
        guard status == .active, let reply = await channel?.send(PreciseCommand.snapshot.json, timeout: Self.snapshotTimeout),
              let snapshot = PreciseMessage.decode(PreciseSnapshot.self, from: reply) else { return nil }
        live = snapshot
        return snapshot
    }

    func label(at point: CGPoint) async -> String? {
        await hit(at: point)?.hit?.label
    }

    func hit(at point: CGPoint) async -> PreciseHitReply? {
        guard status == .active, let reply = await channel?.send(PreciseCommand.hitTest(point).json, timeout: Self.hitTestTimeout) else { return nil }
        return PreciseMessage.decode(PreciseHitReply.self, from: reply)
    }

    func navigationFinished() {
        guard status == .connecting else { return }
        fail("the Precise mode bundle did not load in the web content process")
    }

    func processTerminated() {
        live = nil
        guard status == .active else { return }
        status = .connecting
    }

    func close() {
        channel?.close()
        channel = nil
    }

    func receive(_ json: String) {
        guard let event = PreciseEvent(json: json) else { return }
        switch event {
        case .hello(let version):
            guard version == PreciseMessage.version else {
                fail("the Precise mode bundle speaks protocol \(version), not \(PreciseMessage.version)")
                return
            }
            status = .active
            emit(.pagePrecise, ["mode": "precise"])
        case .load("commit", main: true):
            live = PreciseSnapshot(revision: 0, nodes: [])
        case .load:
            break
        case .request(let method, let url, let redirect):
            emit(.netRequest, ["method": method, "url": url].merging(redirect ? ["redirect": "true"] : [:]) { $1 })
        case .response(let url, let status, let mime):
            emit(.netResponse, ["url": url, "status": "\(status)", "mime": mime])
        case .finished(let url):
            emit(.netFinished, ["url": url])
        case .failed(let url, let error):
            emit(.netFailed, ["url": url, "error": error])
        case .focus(let frame):
            lastFocus = .now
            emit(.formFocus, field(at: frame))
        case .change(let frame, let area):
            emit(.formChange, field(at: frame).merging(["kind": area ? "textarea" : "field"]) { $1 })
        case .submit(let fields):
            emit(.formSubmit, ["fields": "\(fields)"])
        case .changes(let changes):
            live = live?.applying(changes)
        }
    }

    private func field(at frame: CGRect) -> [String: String] {
        guard let node = live?.node(at: frame), let element = PreciseMapping.element(node, viewport: viewport()) else {
            return ["position": "\(Int(frame.midX)),\(Int(frame.midY))"]
        }
        return ["role": element.role.rawValue, "label": element.label]
    }

    private func fail(_ reason: String) {
        status = .unavailable(reason)
        close()
        emit(.pagePrecise, ["mode": "fallback", "reason": reason])
    }
}
