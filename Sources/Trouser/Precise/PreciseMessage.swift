import Foundation

enum PreciseMessage {
    static let version = 1

    static func decode<T: Decodable>(_ type: T.Type, from json: String) -> T? {
        try? JSONDecoder().decode(type, from: Data(json.utf8))
    }
}

enum PreciseCommand: Equatable {
    case snapshot
    case hitTest(CGPoint)

    var json: String {
        let body: [String: Any] = switch self {
        case .snapshot: ["command": "snapshot"]
        case .hitTest(let point): ["command": "hitTest", "x": Double(point.x), "y": Double(point.y)]
        }
        let data = (try? JSONSerialization.data(withJSONObject: body.merging(["v": PreciseMessage.version]) { $1 }, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}

struct PreciseHit: Decodable, Equatable {
    let role: String
    let label: String
}

struct PreciseHitReply: Decodable {
    let hit: PreciseHit?
}

enum PreciseEvent: Equatable {
    case hello(version: Int)
    case load(String, main: Bool)
    case request(method: String, url: String, redirect: Bool)
    case response(url: String, status: Int, mime: String)
    case finished(url: String)
    case failed(url: String, error: String)
    case focus(CGRect)
    case change(CGRect, area: Bool)
    case submit(fields: Int)
    case changes(PreciseChanges)

    private struct Envelope: Decodable {
        let v: Int
        let type: String
        var version: Int?
        var frame: FrameField?
        var url: String?
        var method: String?
        var redirect: Bool?
        var status: Int?
        var mime: String?
        var error: String?
        var kind: String?
        var fields: Int?
    }

    private enum FrameField: Decodable {
        case name(String)
        case rect([Double])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let name = try? container.decode(String.self) {
                self = .name(name)
            } else {
                self = .rect(try container.decode([Double].self))
            }
        }

        var rect: CGRect? {
            guard case .rect(let values) = self, values.count == 4 else { return nil }
            return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        }

        var isMain: Bool {
            if case .name(let name) = self { name == "main" } else { false }
        }
    }

    init?(json: String) {
        guard let envelope = PreciseMessage.decode(Envelope.self, from: json) else { return nil }
        guard envelope.type != "hello" else {
            self = .hello(version: envelope.version ?? envelope.v)
            return
        }
        guard envelope.v == PreciseMessage.version else { return nil }
        let url = envelope.url ?? ""
        switch envelope.type {
        case let type where type.hasPrefix("load."):
            self = .load(String(type.dropFirst(5)), main: envelope.frame?.isMain ?? false)
        case "net.willSend":
            self = .request(method: envelope.method ?? "GET", url: url, redirect: envelope.redirect ?? false)
        case "net.response":
            self = .response(url: url, status: envelope.status ?? 0, mime: envelope.mime ?? "")
        case "net.finish":
            self = .finished(url: url)
        case "net.fail":
            self = .failed(url: url, error: envelope.error ?? "")
        case "form.focus":
            guard let frame = envelope.frame?.rect else { return nil }
            self = .focus(frame)
        case "form.change":
            guard let frame = envelope.frame?.rect else { return nil }
            self = .change(frame, area: envelope.kind == "area")
        case "form.submit":
            self = .submit(fields: envelope.fields ?? 0)
        case "dom.changes":
            guard let changes = PreciseMessage.decode(PreciseChanges.self, from: json) else { return nil }
            self = .changes(changes)
        default:
            return nil
        }
    }
}
