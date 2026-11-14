import AppKit
import Observation
import WebKit

@MainActor
@Observable
final class Workspace {
    static let lastProfileKey = "lastProfile"
    static let defaultProfile = "default"
    private static let backgroundKey = "backgroundMode"

    let policy = Policy()
    private(set) var isBackground = UserDefaults.standard.bool(forKey: backgroundKey)
    @ObservationIgnored private let profiles: ProfileStore
    private var sessions: [String: ProfileSession] = [:]
    @ObservationIgnored private var ruleStores: [String: RuleStore] = [:]
    @ObservationIgnored private var buses: [String: EventBus] = [:]
    @ObservationIgnored private var opening: [String: Task<ProfileSession, Error>] = [:]
    @ObservationIgnored private var settingsStores: [String: ProfileSettingsStore] = [:]

    init(profiles: ProfileStore? = nil) throws {
        self.profiles = try profiles ?? ProfileStore()
        self.profiles.removeOrphanedDataStores()
    }

    var activeProfile: String {
        activeSession?.name ?? Self.defaultProfile
    }

    func events(for name: String) -> EventBus {
        if let bus = buses[name] {
            return bus
        }
        let bus = EventBus(profile: name)
        buses[name] = bus
        return bus
    }

    var profileNames: [String] {
        [Self.defaultProfile] + ((try? profiles.names()) ?? []).filter { $0 != Self.defaultProfile }
    }

    var status: String {
        let lines = profileNames.map { name in
            guard let session = sessions[name] else { return "\(name)  (closed)" }
            let tabs = session.tabs.enumerated().map { index, tab in
                "  \(tab === session.selectedTab ? "*" : " ") \(index + 1)  \(tab.driver.pageDescription)" + (tab.preciseStatus.summary.map { "  [\($0)]" } ?? "")
            }
            let marker = session === activeSession ? "  (open, active)" : "  (open)"
            return (["\(name)\(marker)"] + tabs).joined(separator: "\n")
        }
        let pause = policy.paused ? "paused" : "active"
        let mode = isBackground ? ", background mode" : ""
        return (["trouser: \(pause)\(mode)"] + lines).joined(separator: "\n")
    }

    var activeSession: ProfileSession? {
        UserDefaults.standard.string(forKey: Self.lastProfileKey).flatMap { sessions[$0] }
            ?? sessions[Self.defaultProfile]
            ?? sessions.values.first
    }

    var openSessions: [ProfileSession] {
        sessions.values.sorted { $0.name < $1.name }
    }

    func session(for name: String) -> ProfileSession? {
        sessions[name]
    }

    func rules(for name: String) throws -> RuleStore {
        if let store = ruleStores[name] { return store }
        let store = try profiles.rules(for: name)
        ruleStores[name] = store
        return store
    }

    @discardableResult
    func open(_ name: String, resumingHistory: Bool = false) async throws -> ProfileSession {
        if let session = sessions[name] {
            session.bringToFront()
            return session
        }
        if let pending = opening[name] {
            return try await pending.value
        }
        let task = Task { try await makeSession(name, resumingHistory: resumingHistory) }
        opening[name] = task
        defer { opening[name] = nil }
        return try await task.value
    }

    @discardableResult
    func openDefault() async throws -> ProfileSession {
        try await open(Self.defaultProfile, resumingHistory: true)
    }

    func settings(for name: String) throws -> ProfileSettingsStore {
        if let store = settingsStores[name] {
            return store
        }
        let store = try profiles.settings(for: name)
        settingsStores[name] = store
        return store
    }

    func dataStore(for name: String) throws -> WKWebsiteDataStore {
        try sessions[name]?.dataStore ?? profiles.dataStore(for: name)
    }

    func saveTabs() {
        sessions.values.forEach { $0.saveTabs() }
    }

    func saveSessionCookies() async {
        for session in sessions.values {
            await session.saveSessionCookies()
        }
    }

    private func makeSession(_ name: String, resumingHistory: Bool) async throws -> ProfileSession {
        let dataStore = try profiles.dataStore(for: name)
        let events = events(for: name)
        let session = try ProfileSession(
            name: name,
            dataStore: dataStore,
            history: try profiles.history(for: name),
            downloads: try profiles.downloads(for: name, events: events),
            events: events,
            settings: try settings(for: name),
            restore: try profiles.tabs(for: name),
            atlas: try profiles.atlas(for: name),
            sessionCookies: try profiles.sessionCookies(for: name),
            storageKey: try profiles.storageKey(for: name),
            policy: policy,
            rules: try rules(for: name),
            setPaused: { [unowned self] in setPaused($0) },
            profileNames: { [unowned self] in profileNames }
        )
        try await session.prepare()
        session.onClose = { [unowned self] in sessions[name] = nil }
        session.isBackground = isBackground
        sessions[name] = session
        session.resume(fallback: resumingHistory ? session.history.visits.first?.url : nil)
        return session
    }

    func setBackground(_ background: Bool) {
        isBackground = background
        UserDefaults.standard.set(background, forKey: Self.backgroundKey)
        NSApp.setActivationPolicy(background ? .accessory : .regular)
        sessions.values.forEach { $0.setBackground(background) }
        buses.values.forEach { $0.emit(.backgroundChanged, ["background": "\(background)"]) }
        if background {
            NSApp.hide(nil)
        } else {
            NSApp.unhide(nil)
            sessions.values.forEach { $0.bringToFront() }
            NSApp.activate()
        }
    }

    func setPaused(_ paused: Bool) {
        policy.paused = paused
        buses.values.forEach { $0.emit(.pauseChanged, ["paused": "\(paused)"]) }
        if paused {
            sessions.values.forEach { $0.supervisor.resolve(false) }
        }
    }

    func delete(_ name: String) async throws {
        guard name != Self.defaultProfile else { return }
        if let pending = opening[name] {
            _ = try? await pending.value
        }
        if let session = dropState(for: name) {
            session.closeAll()
            await session.history.flush()
        }
        try await profiles.remove(name)
        try ControlPath.removeCaptures(for: name)
        if UserDefaults.standard.string(forKey: Self.lastProfileKey) == name {
            UserDefaults.standard.removeObject(forKey: Self.lastProfileKey)
        }
    }

    func confirmDeletion(of name: String) -> Bool {
        NSApp.unhide(nil)
        NSApp.activate()
        defer {
            if isBackground { NSApp.hide(nil) }
        }
        return DeleteConfirmation.confirm(name)
    }

    func deleteKeepingWindowOpen(_ name: String) async throws {
        try await delete(name)
        if activeSession == nil {
            try await openDefault()
        }
    }

    func burnEverything() async throws {
        let open = cachedProfiles.compactMap { dropState(for: $0) }
        open.forEach { $0.closeAll() }
        for session in open {
            await session.history.flush()
        }
        try await profiles.removeAll()
        try ControlPath.removeCaptures()
        UserDefaults.standard.removeObject(forKey: Self.lastProfileKey)
    }

    func flushHistory() async {
        for session in sessions.values {
            await session.history.flush()
        }
    }

    private var cachedProfiles: Set<String> {
        Set(sessions.keys).union(ruleStores.keys).union(buses.keys).union(settingsStores.keys)
    }

    private func dropState(for name: String) -> ProfileSession? {
        ruleStores[name] = nil
        buses[name] = nil
        settingsStores[name] = nil
        return sessions.removeValue(forKey: name)
    }
}
