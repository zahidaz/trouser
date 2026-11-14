import Foundation

struct ActionReply: Equatable {
    enum Changes: Equatable {
        case skipped
        case page(PageBrief)
        case diff(ModelDiff, brief: [String] = [])
    }

    let summary: String
    let page: String
    var notes: [String] = []
    var changes: Changes = .skipped

    static let lineLimit = 40

    var changed: Bool? {
        switch changes {
        case .skipped: nil
        case .page: true
        case .diff(let diff, _): !diff.isEmpty
        }
    }

    var text: String {
        ([summary, page] + notes + changeLines).joined(separator: "\n")
    }

    var changeLines: [String] {
        switch changes {
        case .skipped:
            return []
        case .diff(let diff, _) where diff.isEmpty:
            return ["no visible change"]
        case .diff(let diff, let brief):
            let lines = diff.lines
            return Self.capped(!brief.isEmpty && brief.count < lines.count ? brief : lines)
        case .page(let brief):
            return brief.lines
        }
    }

    private static func capped(_ lines: [String]) -> [String] {
        guard lines.count > lineLimit else { return lines }
        let hidden = lines.count - lineLimit
        return Array(lines.prefix(lineLimit)) + ["… \(hidden) more line\(hidden == 1 ? "" : "s"); run: trouser page --all"]
    }
}
