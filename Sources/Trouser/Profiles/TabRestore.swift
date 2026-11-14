import Foundation

struct SavedTab: Codable, Equatable, Sendable {
    let url: URL
    let title: String
    let state: Data?
}

struct TabRestoreBook: Equatable {
    private var closing: [SavedTab]?

    mutating func willClose(_ open: @autoclosure () -> [SavedTab]) -> Bool {
        guard closing == nil else { return false }
        closing = open()
        return true
    }

    mutating func settle(remaining: [SavedTab]) -> [SavedTab] {
        defer { closing = nil }
        return remaining.isEmpty ? closing ?? [] : remaining
    }
}

@MainActor
struct TabRestoreStore {
    let fileURL: URL

    func load() -> [SavedTab] {
        (try? JSONDecoder().decode([SavedTab].self, from: Data(contentsOf: fileURL))) ?? []
    }

    func save(_ tabs: [SavedTab]) {
        try? JSONEncoder().encode(tabs).write(to: fileURL, options: .atomic)
    }
}
