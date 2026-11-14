import Foundation

struct Response: Codable, Equatable {
    var ok: Bool
    var message: String
    var file: String?

    static func success(_ message: String, file: URL? = nil) -> Response {
        Response(ok: true, message: message, file: file?.path)
    }

    static func failure(_ message: String) -> Response {
        Response(ok: false, message: message)
    }
}

enum Frame: Equatable {
    case output(String)
    case response(Response)
}

extension Frame: Codable {
    private enum CodingKeys: CodingKey {
        case output
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let line = try container.decodeIfPresent(String.self, forKey: .output) {
            self = .output(line)
        } else {
            self = .response(try Response(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .output(let line):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(line, forKey: .output)
        case .response(let response):
            try response.encode(to: encoder)
        }
    }
}

struct Output: Sendable {
    let send: @Sendable (String) -> Void

    func callAsFunction(_ line: String) {
        send(line)
    }
}

enum ControlError: LocalizedError {
    case appUnavailable
    case connectionClosed
    case requestTooLarge
    case system(String)

    var errorDescription: String? {
        switch self {
        case .appUnavailable: "Trouser did not start; open it from /Applications and retry"
        case .connectionClosed: "Trouser closed the connection"
        case .requestTooLarge: "request exceeds 1 MB"
        case .system(let operation): "\(operation) failed: \(String(cString: strerror(errno)))"
        }
    }
}
