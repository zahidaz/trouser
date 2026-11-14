import Foundation

struct Event: Codable, Equatable, Identifiable, Sendable {
    let sequence: Int
    let date: Date
    let profile: String
    let tab: Int?
    let type: EventType
    let fields: [String: String]

    var id: Int { sequence }

    var line: String {
        let time = date.formatted(Date.ISO8601FormatStyle(timeZone: .current).time(includingFractionalSeconds: true))
        let source = tab.map { "\(profile)[\($0)]" } ?? profile
        let details = fields.sorted { $0.key < $1.key }.map { "\($0.key)=\(Self.quoted($0.value))" }
        return (["#\(sequence)", time, source, type.rawValue] + details).joined(separator: " ")
    }

    var note: String? {
        switch type {
        case .navigationFailed where !Self.benignFailures.contains(fields["code"] ?? ""):
            "navigation failed: \(fields["error"] ?? "unknown error")"
        case .navigationResponse where fields["frame"] == "main" && (Int(fields["status"] ?? "") ?? 0) >= 400:
            "HTTP \(fields["status"] ?? "")"
        case .downloadStarted:
            "download started: \(fields["file"] ?? "")"
        case .processTerminated:
            "web content process terminated"
        default:
            nil
        }
    }

    var isConnectionLoss: Bool {
        type == .navigationFailed && fields["code"] == "\(NSURLErrorNetworkConnectionLost)"
    }

    var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
        }
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    private static let benignFailures: Set<String> = ["\(NSURLErrorCancelled)", "102"]

    private static func quoted(_ value: String) -> String {
        guard value.isEmpty || value.contains(where: { $0.isWhitespace || $0 == "\"" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: " ") + "\""
    }
}

extension Sequence<Event> {
    var navigationFailure: Event? {
        reduce(nil) { failure, event in
            switch event.type {
            case .navigationCommitted: nil
            case .navigationFailed where event.note != nil: event
            default: failure
            }
        }
    }
}
