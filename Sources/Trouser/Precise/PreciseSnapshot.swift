import Foundation

struct PreciseNode: Codable, Equatable, Sendable {
    let key: String
    let role: String
    var parent: String?
    var subrole: String?
    var title: String?
    var description: String?
    var dom: String?
    var value: String?
    var number: Double?
    var placeholder: String?
    var url: String?
    var frame: [Double]?
    var disabled: Bool?
    var focused: Bool?
    var required: Bool?
    var selected: Bool?
    var expanded: Bool?
    var invalid: Bool?
    var readonly: Bool?

    var rect: CGRect? {
        guard let frame, frame.count == 4, frame[2] > 0, frame[3] > 0 else { return nil }
        return CGRect(x: frame[0], y: frame[1], width: frame[2], height: frame[3])
    }

    var identity: String {
        dom.map { "#\($0)" } ?? key
    }
}

struct PreciseChanges: Decodable, Equatable, Sendable {
    let base: Int
    let revision: Int
    let upsert: [PreciseNode]
    let remove: [String]
    let order: [String]?
}

struct PreciseSnapshot: Decodable, Equatable, Sendable {
    let revision: Int
    let nodes: [PreciseNode]

    func applying(_ changes: PreciseChanges) -> PreciseSnapshot? {
        guard changes.base == revision else { return nil }
        var byKey = Dictionary(nodes.map { ($0.key, $0) }, uniquingKeysWith: { _, last in last })
        changes.remove.forEach { byKey[$0] = nil }
        changes.upsert.forEach { byKey[$0.key] = $0 }
        let order = changes.order ?? nodes.map(\.key) + changes.upsert.map(\.key).filter { key in !nodes.contains { $0.key == key } }
        return PreciseSnapshot(revision: changes.revision, nodes: order.compactMap { byKey[$0] })
    }

    func node(at frame: CGRect) -> PreciseNode? {
        nodes.first { node in
            node.role != "AXStaticText" && node.rect.map { Self.same($0, frame) } ?? false
        }
    }

    private static func same(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= 1 && abs(lhs.minY - rhs.minY) <= 1 && abs(lhs.width - rhs.width) <= 1 && abs(lhs.height - rhs.height) <= 1
    }
}
