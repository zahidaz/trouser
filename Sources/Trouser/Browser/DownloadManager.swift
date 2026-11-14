import Foundation
import Observation
import WebKit

@MainActor
@Observable
final class DownloadManager: NSObject, WKDownloadDelegate {
    enum State: Codable, Equatable {
        case running, finished
        case failed(String)
    }

    struct Item: Codable, Identifiable {
        var id = UUID()
        let file: URL
        let date: Date
        var state: State
        var progress: Double?
    }

    private(set) var items: [Item]
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let events: EventBus
    @ObservationIgnored private var milestones: [Item.ID: Int] = [:]
    @ObservationIgnored private var active: [ObjectIdentifier: Item.ID] = [:]
    @ObservationIgnored private var observations: [Item.ID: NSKeyValueObservation] = [:]

    private static let limit = 200

    init(fileURL: URL, events: EventBus) {
        self.fileURL = fileURL
        self.events = events
        let saved = (try? JSONDecoder().decode([Item].self, from: Data(contentsOf: fileURL))) ?? []
        items = saved.map { item in
            var item = item
            if item.state == .running {
                item.state = .failed("Interrupted")
            }
            return item
        }
    }

    var isDownloading: Bool {
        items.contains { $0.state == .running }
    }

    var overallProgress: Double? {
        let running = items.filter { $0.state == .running }
        guard !running.isEmpty else { return nil }
        return running.map { $0.progress ?? 0 }.reduce(0, +) / Double(running.count)
    }

    var summary: String {
        guard !items.isEmpty else { return "no downloads" }
        return items.map { item in
            let state = switch item.state {
            case .running: "downloading \(Int((item.progress ?? 0) * 100))%"
            case .finished: "finished"
            case .failed(let reason): "failed: \(reason)"
            }
            return "\(state)  \(item.file.path)"
        }.joined(separator: "\n")
    }

    func track(_ download: WKDownload) {
        download.delegate = self
    }

    func clear() {
        items.removeAll { $0.state != .running }
        save()
    }

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String
    ) async -> URL? {
        let file = Self.destination(for: suggestedFilename)
        let item = Item(file: file, date: Date(), state: .running, progress: 0)
        items.insert(item, at: 0)
        active[ObjectIdentifier(download)] = item.id
        events.emit(.downloadStarted, ["file": file.path, "url": response.url?.absoluteString ?? ""])
        observations[item.id] = download.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            let fraction = progress.fractionCompleted
            Task { @MainActor in self?.setProgress(fraction, for: item.id) }
        }
        return file
    }

    func downloadDidFinish(_ download: WKDownload) {
        update(download, .finished)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        update(download, .failed(error.localizedDescription))
    }

    private func setProgress(_ fraction: Double, for id: Item.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].state == .running else { return }
        items[index].progress = fraction
        let milestone = Int(fraction * 4) * 25
        guard (25...75).contains(milestone), milestone > milestones[id, default: 0] else { return }
        milestones[id] = milestone
        events.emit(.downloadProgress, ["file": items[index].file.path, "progress": "\(milestone)%"])
    }

    private func update(_ download: WKDownload, _ state: State) {
        guard let id = active.removeValue(forKey: ObjectIdentifier(download)),
              let index = items.firstIndex(where: { $0.id == id }) else { return }
        observations.removeValue(forKey: id)
        milestones.removeValue(forKey: id)
        items[index].state = state
        switch state {
        case .failed(let reason): events.emit(.downloadFailed, ["file": items[index].file.path, "error": reason])
        default: events.emit(.downloadFinished, ["file": items[index].file.path])
        }
        items[index].progress = nil
        save()
    }

    private func save() {
        let finished = Array(items.filter { $0.state != .running }.prefix(Self.limit))
        try? JSONEncoder().encode(finished).write(to: fileURL, options: .atomic)
    }

    private static func destination(for suggestedFilename: String) -> URL {
        let directory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].resolvingSymlinksInPath()
        let cleaned = suggestedFilename
            .components(separatedBy: CharacterSet(charactersIn: "/:\\"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        let name = cleaned.isEmpty ? "download" : cleaned
        let base = (name as NSString).deletingPathExtension
        let pathExtension = (name as NSString).pathExtension

        var candidate = directory.appendingPathComponent(name)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let numbered = pathExtension.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(pathExtension)"
            candidate = directory.appendingPathComponent(numbered)
            number += 1
        }
        return candidate
    }
}
