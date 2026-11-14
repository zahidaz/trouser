import Foundation

extension URL {
    init?(userInput: String) {
        let text = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let url = Self.resolve(text), url.isWeb else { return nil }
        self = url
    }

    var isWeb: Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private static func resolve(_ text: String) -> URL? {
        if text.wholeMatch(of: /[A-Za-z][A-Za-z0-9+.\-]*:(?!\d).*/) != nil {
            return URL(string: text)
        }
        if !text.contains(" "), text.contains(".") || text.hasPrefix("localhost") {
            return URL(string: "https://\(text)")
        }
        var search = URLComponents(string: "https://duckduckgo.com/")
        search?.queryItems = [URLQueryItem(name: "q", value: text)]
        return search?.url
    }
}
