import Foundation

enum ControlPath {
    static let socketOverride = ProcessInfo.processInfo.environment["TROUSER_SOCKET"]
    static let socket = socketOverride ?? NSTemporaryDirectory() + "trouser.sock"
    private static let launchMarker = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("trouser.cli-launch")
    private static let launchMarkerLifetime: TimeInterval = 15

    static func markLaunchFromCLI() throws {
        try Data().write(to: launchMarker, options: .atomic)
    }

    static func consumeLaunchFromCLI() -> Bool {
        let created = (try? launchMarker.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        try? FileManager.default.removeItem(at: launchMarker)
        return created.map { Date().timeIntervalSince($0) < launchMarkerLifetime } ?? false
    }

    static let captures = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("captures", isDirectory: true)

    static func capture(for profile: String, extension fileExtension: String) throws -> URL {
        try FileManager.default.createDirectory(at: captures, withIntermediateDirectories: true)
        return captures.appendingPathComponent(profile).appendingPathExtension(fileExtension)
    }

    static func removeCaptures(for profile: String, in directory: URL = captures) throws {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.lastPathComponent.hasPrefix("\(profile).") {
            try FileManager.default.removeItem(at: file)
        }
    }

    static func removeCaptures() throws {
        guard FileManager.default.fileExists(atPath: captures.path) else { return }
        try FileManager.default.removeItem(at: captures)
    }
}
