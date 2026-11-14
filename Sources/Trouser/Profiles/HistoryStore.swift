import Foundation
import Observation

@MainActor
@Observable
final class HistoryStore {
    struct Visit: Codable, Identifiable, Equatable {
        let url: URL
        let title: String
        let date: Date

        var id: URL { url }
    }

    private(set) var visits: [Visit]
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var pendingWrite: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    private static let limit = 500

    init(fileURL: URL) {
        self.fileURL = fileURL
        visits = (try? JSONDecoder().decode([Visit].self, from: Data(contentsOf: fileURL))) ?? []
    }

    func record(_ url: URL, title: String) {
        guard url.scheme == "https" || url.scheme == "http" else { return }
        visits.removeAll { $0.url == url }
        visits.insert(Visit(url: url, title: title.isEmpty ? url.host() ?? url.absoluteString : title, date: Date()), at: 0)
        if visits.count > Self.limit {
            visits.removeLast(visits.count - Self.limit)
        }
        save()
    }

    func remove(_ url: URL) {
        visits.removeAll { $0.url == url }
        save()
    }

    func removeAll() {
        visits.removeAll()
        save()
    }

    func flush() async {
        await pendingWrite?.value
    }

    private func save() {
        generation += 1
        let current = generation
        let snapshot = visits
        let url = fileURL
        let previous = pendingWrite
        pendingWrite = Task {
            await previous?.value
            guard generation == current else { return }
            await Self.write(snapshot, to: url)
        }
    }

    @concurrent
    private static func write(_ visits: [Visit], to url: URL) async {
        try? JSONEncoder().encode(visits).write(to: url, options: .atomic)
    }
}
