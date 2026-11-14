import Foundation

enum PreciseStatus: Equatable, Sendable {
    case off
    case connecting
    case active
    case unavailable(String)

    var name: String? {
        switch self {
        case .off: nil
        case .connecting: "connecting"
        case .active: "active"
        case .unavailable: "unavailable"
        }
    }

    var summary: String? {
        switch self {
        case .off: nil
        case .connecting: "precise mode connecting"
        case .active: "precise mode"
        case .unavailable(let reason): "precise mode unavailable (\(reason)), capture model"
        }
    }

    static func select(enabled: Bool, bundleExists: Bool, problem: String?) -> PreciseStatus {
        guard enabled else { return .off }
        if let problem { return .unavailable(problem) }
        return bundleExists ? .connecting : .unavailable("the Precise mode bundle is missing from Trouser.app")
    }

    static func report(enabled: Bool, tabs: [PreciseStatus]) -> String {
        let active = tabs.filter { $0 == .active }.count
        let reasons = tabs.compactMap { status -> String? in
            if case .unavailable(let reason) = status { reason } else { nil }
        }
        guard enabled || active > 0 else { return "off" }
        var parts = [enabled ? "on" : "off for new tabs", "\(active) of \(tabs.count) tabs precise"]
        if let reason = reasons.first {
            parts.append("unavailable: \(reason), using the capture model")
        }
        return parts.joined(separator: ", ")
    }
}
