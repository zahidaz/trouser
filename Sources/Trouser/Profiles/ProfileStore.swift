import Foundation
import WebKit

enum ProfileError: LocalizedError {
    case invalidName(String)

    var errorDescription: String? {
        switch self {
        case .invalidName(let name):
            "Invalid profile name “\(name)”. Use up to 40 lowercase letters, digits, - or _."
        }
    }
}

enum ProfileFile: CaseIterable {
    case history, downloads, settings, tabs, atlas, sessionCookies, storageKey, rules

    var isPolicy: Bool {
        self == .rules
    }

    func fileName(for profile: String) -> String {
        switch self {
        case .history, .rules: "\(profile).json"
        case .downloads: "\(profile).downloads.json"
        case .settings: "\(profile).settings.json"
        case .tabs: "\(profile).tabs.json"
        case .atlas: "\(profile).atlas.json"
        case .sessionCookies: "\(profile).session-cookies.json"
        case .storageKey: "\(profile).storage-key"
        }
    }
}

@MainActor
struct ProfileStore {
    private let fileURL: URL
    private let dataStoreDirectory: URL?
    private let historyDirectory: URL
    private let policyDirectory: URL
    private static let storageKeyLength = 16

    init(directory custom: URL? = nil) throws {
        let directory = try custom ?? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Trouser", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("profiles.json")
        dataStoreDirectory = custom == nil && NSHomeDirectory().contains("/Library/Containers/")
            ? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/WebKit/WebsiteDataStore", isDirectory: true)
            : nil
        historyDirectory = directory.appendingPathComponent("history", isDirectory: true)
        policyDirectory = directory.appendingPathComponent("policy", isDirectory: true)
    }

    func names() throws -> [String] {
        try load().keys.sorted()
    }

    func dataStore(for name: String) throws -> WKWebsiteDataStore {
        try Self.validate(name)
        var profiles = try load()
        if profiles[name] == nil {
            profiles[name] = UUID()
            try save(profiles)
        }
        return WKWebsiteDataStore(forIdentifier: profiles[name]!)
    }

    func history(for name: String) throws -> HistoryStore {
        HistoryStore(fileURL: try file(.history, for: name))
    }

    func downloads(for name: String, events: EventBus) throws -> DownloadManager {
        DownloadManager(fileURL: try file(.downloads, for: name), events: events)
    }

    func rules(for name: String) throws -> RuleStore {
        try Self.validate(name)
        return RuleStore(fileURL: try file(.rules, for: name))
    }

    func settings(for name: String) throws -> ProfileSettingsStore {
        ProfileSettingsStore(profile: name, fileURL: try file(.settings, for: name))
    }

    func tabs(for name: String) throws -> TabRestoreStore {
        TabRestoreStore(fileURL: try file(.tabs, for: name))
    }

    func sessionCookies(for name: String) throws -> SessionCookieStore {
        SessionCookieStore(fileURL: try file(.sessionCookies, for: name))
    }

    func storageKey(for name: String) throws -> Data {
        let location = try file(.storageKey, for: name)
        if let key = try? Data(contentsOf: location), key.count == Self.storageKeyLength {
            return key
        }
        var generator = SystemRandomNumberGenerator()
        let key = Data((0..<Self.storageKeyLength).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
        try key.write(to: location, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: location.path)
        return key
    }

    func atlas(for name: String) throws -> SiteAtlasStore {
        SiteAtlasStore(fileURL: try file(.atlas, for: name))
    }

    func remove(_ name: String) async throws {
        var profiles = try load()
        if let identifier = profiles.removeValue(forKey: name) {
            await erase(identifier)
            try save(profiles)
        }
        for kind in ProfileFile.allCases {
            try removeIfPresent(url(kind, for: name))
        }
    }

    func removeAll() async throws {
        for identifier in try load().values {
            await erase(identifier)
        }
        try removeIfPresent(fileURL)
        try removeIfPresent(historyDirectory)
    }

    func removeOrphanedDataStores() {
        guard let dataStoreDirectory, let profiles = try? load(),
              let folders = try? FileManager.default.contentsOfDirectory(at: dataStoreDirectory, includingPropertiesForKeys: nil)
        else { return }
        for folder in Self.orphans(folders, keeping: Set(profiles.values)) {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    static func orphans(_ folders: [URL], keeping identifiers: Set<UUID>) -> [URL] {
        folders.filter { folder in
            guard let identifier = UUID(uuidString: folder.lastPathComponent) else { return false }
            return !identifiers.contains(identifier)
        }
    }

    private func erase(_ identifier: UUID) async {
        await WKWebsiteDataStore(forIdentifier: identifier).removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    }

    func url(_ kind: ProfileFile, for name: String) -> URL {
        let directory = kind.isPolicy ? policyDirectory : historyDirectory
        return directory.appendingPathComponent(kind.fileName(for: name))
    }

    private func file(_ kind: ProfileFile, for name: String) throws -> URL {
        let location = url(kind, for: name)
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        return location
    }

    private static func validate(_ name: String) throws {
        guard name.wholeMatch(of: /[a-z0-9][a-z0-9_-]{0,39}/) != nil else {
            throw ProfileError.invalidName(name)
        }
    }

    private func removeIfPresent(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func load() throws -> [String: UUID] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        return try JSONDecoder().decode([String: UUID].self, from: Data(contentsOf: fileURL))
    }

    private func save(_ profiles: [String: UUID]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(profiles).write(to: fileURL, options: .atomic)
    }
}
