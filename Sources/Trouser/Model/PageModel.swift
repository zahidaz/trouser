import Foundation

struct PageInfo: Equatable, Encodable {
    var url: URL?
    var title: String
    var loading: Bool
    var progress: Double
    var secure: Bool
    var onlySecureContent: Bool
    var generation: Int
    var viewport: CGSize
    var precise = PreciseStatus.off
    var placed = true

    var document: String? {
        Self.document(of: url)
    }

    static func document(of url: URL?) -> String? {
        url?.absoluteString.split(separator: "#", maxSplits: 1).first.map(String.init)
    }

    var description: String {
        let title = title.isEmpty ? "Untitled" : title
        let flags = [
            "generation \(generation)",
            loading ? "loading \(Int(progress * 100))%" : "loaded",
            secure ? "secure" : "not secure",
            "viewport \(Int(viewport.width))×\(Int(viewport.height))"
        ] + [precise.summary, placed ? nil : "positions unknown: could not tell where the page is scrolled to"].compactMap { $0 }
        return "\(title) — \(url?.absoluteString ?? "about:blank")\n\(flags.joined(separator: ", "))"
    }

    private enum CodingKeys: String, CodingKey {
        case url, title, loading, progress, secure, onlySecureContent, generation, viewport, precise, placed
    }

    private struct Size: Encodable {
        let width: Int
        let height: Int
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url?.absoluteString, forKey: .url)
        try container.encode(title, forKey: .title)
        try container.encode(loading, forKey: .loading)
        try container.encode((progress * 100).rounded() / 100, forKey: .progress)
        try container.encode(secure, forKey: .secure)
        try container.encode(onlySecureContent, forKey: .onlySecureContent)
        try container.encode(generation, forKey: .generation)
        try container.encode(Size(width: Int(viewport.width), height: Int(viewport.height)), forKey: .viewport)
        try container.encode(precise.name, forKey: .precise)
        try container.encode(placed, forKey: .placed)
    }
}

struct PageModel: Equatable, Encodable {
    static let schema = 1

    let page: PageInfo
    let focus: String?
    let elements: [ModelElement]

    func element(_ id: String) -> ModelElement? {
        elements.first { $0.id == id }
    }

    func element(at point: CGPoint) -> ModelElement? {
        elements
            .filter { $0.frame?.contains(point) ?? false }
            .min { lhs, rhs in
                (lhs.source == .dom ? 0 : 1, area(lhs)) < (rhs.source == .dom ? 0 : 1, area(rhs))
            }
    }

    private func area(_ element: ModelElement) -> CGFloat {
        element.frame.map { $0.width * $0.height } ?? 0
    }

    var description: String {
        let visible = elements.filter(\.visible).count
        let focus = focus.map { ", focus \($0)" } ?? ""
        let header = "\(page.description)\n\(elements.count) elements, \(visible) visible\(focus)"
        return ([header] + elements.map(\.description)).joined(separator: "\n")
    }

    func json() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }

    private enum CodingKeys: String, CodingKey {
        case schema, page, focus, elements
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.schema, forKey: .schema)
        try container.encode(page, forKey: .page)
        try container.encode(focus, forKey: .focus)
        try container.encode(elements, forKey: .elements)
    }
}
