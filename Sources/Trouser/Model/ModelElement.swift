import Foundation

struct ModelElement: Equatable, Encodable {
    var id = ""
    let role: ElementRole
    let label: String
    var value: String?
    var placeholder: String?
    var states: [ElementState] = []
    var frame: CGRect?
    var url: URL?
    var context: String?
    let source: ElementSource
    var identity: String?
    var offscreen = false

    var visible: Bool {
        frame != nil && !offscreen
    }

    var center: CGPoint? {
        frame.map { CGPoint(x: $0.midX.rounded(), y: $0.midY.rounded()) }
    }

    var position: String {
        guard let center else { return "unplaced" }
        let point = "\(Int(center.x)),\(Int(center.y))"
        return offscreen ? "offscreen \(point)" : point
    }

    var name: String {
        label.isEmpty ? "→ \(context ?? "")" : label
    }

    var description: String {
        var line = "\(id.padding(toLength: max(5, id.count + 1), withPad: " ", startingAt: 0))\(role.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0))“\(name)”"
        if let value {
            line += " = “\(value)”"
        } else if let placeholder, role.showsValue {
            line += " (empty, “\(placeholder)”)"
        }
        line += "  \(position)"
        if !states.isEmpty {
            line += "  \(states.map(\.rawValue).joined(separator: " "))"
        }
        if let url {
            line += "  → \(url.absoluteString)"
        }
        if source == .ocr {
            line += "  [ocr]"
        }
        return line
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, label, value, placeholder, states, frame, center, visible, source, url, context
    }

    private struct Point: Encodable {
        let x: Int
        let y: Int
    }

    private struct Frame: Encodable {
        let x: Int
        let y: Int
        let width: Int
        let height: Int
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(label, forKey: .label)
        try container.encode(value, forKey: .value)
        try container.encode(placeholder, forKey: .placeholder)
        try container.encode(states, forKey: .states)
        try container.encode(frame.map {
            Frame(x: Int($0.minX.rounded()), y: Int($0.minY.rounded()), width: Int($0.width.rounded()), height: Int($0.height.rounded()))
        }, forKey: .frame)
        try container.encode(center.map { Point(x: Int($0.x), y: Int($0.y)) }, forKey: .center)
        try container.encode(visible, forKey: .visible)
        try container.encode(source, forKey: .source)
        try container.encode(url?.absoluteString, forKey: .url)
        try container.encode(context, forKey: .context)
    }
}
