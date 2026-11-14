import Foundation

enum MediaDevice: String, CaseIterable, Identifiable, Codable, CodingKeyRepresentable, Sendable {
    case camera, microphone

    var id: Self { self }

    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .camera: "camera"
        case .microphone: "mic"
        }
    }
}

enum MediaMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case allow, ask, deny

    var id: Self { self }

    var title: String { rawValue.capitalized }

    static func strictest(_ modes: [MediaMode]) -> MediaMode {
        if modes.contains(.deny) || modes.isEmpty { return .deny }
        return modes.contains(.ask) ? .ask : .allow
    }
}

struct SiteRule: Codable, Hashable, Identifiable, Sendable {
    var pattern: HostPattern
    var actions: [ActionKind: Mode] = [:]
    var media: [MediaDevice: MediaMode] = [:]

    var id: HostPattern { pattern }

    var summary: String {
        let actions = ActionKind.allCases.compactMap { kind in self.actions[kind].map { "\(kind.rawValue) \($0.rawValue)" } }
        let media = MediaDevice.allCases.compactMap { device in self.media[device].map { "\(device.rawValue) \($0.rawValue)" } }
        let parts = actions + media
        return parts.isEmpty ? "no overrides" : parts.joined(separator: ", ")
    }
}
