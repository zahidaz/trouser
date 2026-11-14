import Foundation

enum ModelError: LocalizedError {
    case unknownElement(String)
    case notFillable(ModelElement)
    case notPlaceable(ModelElement)
    case noMatch
    case noIntentMatch(String)
    case ambiguous(String, [IntentMatch])

    var isMiss: Bool {
        switch self {
        case .unknownElement, .noMatch, .noIntentMatch: true
        case .notFillable, .notPlaceable, .ambiguous: false
        }
    }

    var errorDescription: String? {
        switch self {
        case .unknownElement(let id):
            "no element \(id) on the current page; run: trouser page --all"
        case .notFillable(let element):
            "\(element.id) is a \(element.role.rawValue), not a text field; use: trouser tap \(element.id)"
        case .notPlaceable(let element):
            "\(element.id) “\(element.label)” has no position on screen; use coordinates from: trouser screenshot"
        case .noMatch:
            "no element matches; run: trouser page --all"
        case .noIntentMatch(let target):
            "nothing on the page matches “\(target)”; run: trouser page"
        case .ambiguous(let target, let candidates):
            (["“\(target)” is ambiguous, nothing was done; use an id, or more specific words:"] + candidates.map { "  \($0.description)" })
                .joined(separator: "\n")
        }
    }
}
