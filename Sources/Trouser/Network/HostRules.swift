import Foundation

struct HostRules: Equatable, Sendable {
    var allowed: [String] = []
    var blocked: [String] = []

    func permits(_ host: String) -> Bool {
        let host = Self.normalize(host)
        guard !blocked.contains(where: { Self.matches(host, pattern: $0) }) else { return false }
        return allowed.isEmpty || allowed.contains { Self.matches(host, pattern: $0) }
    }

    static func matches(_ host: String, pattern: String) -> Bool {
        let host = normalize(host)
        let pattern = normalize(pattern)
        guard !pattern.isEmpty else { return false }
        if pattern.hasPrefix("*.") {
            return host.hasSuffix(String(pattern.dropFirst()))
        }
        return host == pattern || host.hasSuffix(".\(pattern)")
    }

    static func normalize(_ host: String) -> String {
        var host = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if host.hasPrefix("["), host.hasSuffix("]") {
            host = String(host.dropFirst().dropLast())
        }
        while host.hasSuffix(".") {
            host.removeLast()
        }
        return host
    }
}
