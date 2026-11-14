import Foundation

struct PageSignature: Codable, Hashable {
    let host: String
    let path: String
    let title: String

    init(host: String, path: String, title: String) {
        self.host = host
        self.path = path
        self.title = title
    }

    init?(url: URL?, title: String?) {
        guard let url, let host = url.host() else { return nil }
        self.host = url.port.map { "\(host):\($0)" } ?? host
        path = Self.pattern(of: url.path())
        self.title = (title ?? "").numberless
    }

    var name: String {
        title.isEmpty ? "\(host)\(path)" : title
    }

    var description: String {
        "“\(name)” (\(host)\(path))"
    }

    func matches(_ query: String) -> Bool {
        let key = query.matchKey
        return title.matchKey.contains(key) || path.lowercased().contains(key.replacingOccurrences(of: " ", with: "-"))
    }

    static func pattern(of path: String) -> String {
        let segments = path.split(separator: "/", omittingEmptySubsequences: true).map { segment in
            isIdentifier(segment) ? "*" : String(segment)
        }
        return "/" + segments.joined(separator: "/")
    }

    private static func isIdentifier(_ segment: Substring) -> Bool {
        let digits = segment.filter(\.isNumber).count
        return digits == segment.count || (segment.count >= identifierLength && digits > 0)
    }

    private static let identifierLength = 8
}
