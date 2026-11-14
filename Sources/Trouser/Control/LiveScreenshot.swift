import CoreGraphics
import Foundation

@MainActor
struct LiveScreenshot {
    let session: ProfileSession
    let every: Duration

    nonisolated static let defaultInterval: Duration = .seconds(1)
    nonisolated static let intervalRange = 0.2...60.0
    static let idleRefreshes = 5
    nonisolated static let quality = 0.4
    nonisolated static let fileExtension = "live.jpg"

    func run(output: Output) async -> Response {
        guard session.settings.settings.liveScreenshot else { return .failure(LiveScreenshotError.off.localizedDescription) }
        let summary = "stream live screenshot every \(Self.describe(every))"
        let entry: Supervisor.Entry.ID
        switch await session.supervisor.authorize(.view, summary, context: ActionContext(host: currentHost)) {
        case .granted(let id): entry = id
        case .refused(let reason): return .failure("\(summary): \(reason)")
        }
        let file: URL
        do {
            file = try ControlPath.capture(for: session.name, extension: Self.fileExtension)
        } catch {
            session.supervisor.finish(entry, .failed(error.localizedDescription))
            return .failure(error.localizedDescription)
        }
        output(file.path)
        session.liveFile = file
        let reason = await stream(to: file)
        session.liveFile = nil
        try? FileManager.default.removeItem(at: file)
        session.supervisor.finish(entry, .done)
        return .success(reason)
    }

    private func stream(to file: URL) async -> String {
        var lastCapture: ContinuousClock.Instant?
        while !Task.isCancelled {
            guard let tab = session.selectedTab else { return "stopped: the profile has no open tab" }
            guard session.settings.settings.liveScreenshot else { return "stopped: live screenshot was turned off" }
            if isBlocked {
                try? FileManager.default.removeItem(at: file)
                lastCapture = nil
            } else if tab.webView.url != nil, Self.isDue(now: .now, lastCapture: lastCapture, lastActivity: session.lastActivity, idleRefresh: every * Self.idleRefreshes) {
                lastCapture = .now
                await Self.capture(tab, to: file)
            }
            try? await Task.sleep(for: every)
        }
        return ""
    }

    private var currentHost: String? {
        session.selectedTab?.webView.url?.host()
    }

    private var isBlocked: Bool {
        session.supervisor.decision(for: .view, context: ActionContext(host: currentHost)).mode == .block
    }

    static func refresh(in session: ProfileSession) async {
        guard let file = session.liveFile, let tab = session.selectedTab,
              session.supervisor.decision(for: .view, context: ActionContext(host: tab.webView.url?.host())).mode != .block
        else { return }
        await capture(tab, to: file)
    }

    private static func capture(_ tab: BrowserWindowController, to file: URL) async {
        guard let image = try? await tab.driver.snapshot(onePixelPerPoint: true) else { return }
        try? await write(image, size: tab.webView.bounds.size, to: file)
    }

    nonisolated static func write(_ image: CGImage, size: CGSize, to file: URL) async throws {
        try await PageImage.write(image, size: size, as: .jpeg, quality: quality, to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    static func isDue(now: ContinuousClock.Instant, lastCapture: ContinuousClock.Instant?, lastActivity: ContinuousClock.Instant?, idleRefresh: Duration) -> Bool {
        guard let lastCapture else { return true }
        if let lastActivity, lastActivity >= lastCapture { return true }
        return now - lastCapture >= idleRefresh
    }

    nonisolated static func interval(arguments: [String]) throws -> Duration {
        guard !arguments.isEmpty else { return defaultInterval }
        guard arguments.count == 2, arguments[0] == "--every" else { throw CommandError.usage }
        guard let seconds = Double(arguments[1]), intervalRange.contains(seconds) else {
            throw CommandError.invalid("expected seconds between \(intervalRange.lowerBound) and \(Int(intervalRange.upperBound)), got “\(arguments[1])”")
        }
        return .milliseconds(Int((seconds * 1000).rounded()))
    }

    private static func describe(_ interval: Duration) -> String {
        let seconds = Double(interval.components.seconds) + Double(interval.components.attoseconds) / 1e18
        return seconds.formatted(.number.precision(.fractionLength(0...2))) + " s"
    }
}

enum LiveScreenshotError: LocalizedError {
    case off

    var errorDescription: String? {
        "live screenshot is off for this profile; it can be turned on in Settings"
    }
}
