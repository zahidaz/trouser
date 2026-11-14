import Foundation
import Testing
@testable import Trouser

@MainActor
struct ProfileSettingsTests {
    private let file = FileManager.default.temporaryDirectory.appendingPathComponent("trouser-settings-\(UUID().uuidString).json")

    @Test func defaultsKeepJavaScriptAndSafariIdentity() {
        let settings = ProfileSettings()
        #expect(settings.javaScript)
        #expect(!settings.lockdownMode)
        #expect(settings.customUserAgent == nil)
        #expect(settings.pageZoom == 1)
        #expect(settings.viewport == nil)
        #expect(settings.inactiveScheduling == .suspend)
        #expect(!settings.preciseMode)
    }

    @Test func persistsPreciseModeAndDefaultsItOff() throws {
        let store = ProfileSettingsStore(profile: "work", fileURL: file)
        store.settings.preciseMode = true
        #expect(ProfileSettingsStore(profile: "work", fileURL: file).settings.preciseMode)
        try? FileManager.default.removeItem(at: file)
        let older = try JSONDecoder().decode(ProfileSettings.self, from: Data(#"{"javaScript": false}"#.utf8))
        #expect(!older.preciseMode)
    }

    @Test func persistsChanges() {
        let store = ProfileSettingsStore(profile: "work", fileURL: file)
        store.settings.javaScript = false
        store.settings.viewport = .standard
        store.settings.blockedHosts = ["tracker.example"]
        let reloaded = ProfileSettingsStore(profile: "work", fileURL: file).settings
        #expect(reloaded == store.settings)
        #expect(reloaded.viewport == ProfileSettings.Viewport(width: 1280, height: 800))
        try? FileManager.default.removeItem(at: file)
    }

    @Test func fillsMissingKeysWithDefaultsAndClampsZoom() throws {
        let json = #"{"blockTrackers": true, "pageZoom": 9, "userAgent": "  "}"#
        let settings = try JSONDecoder().decode(ProfileSettings.self, from: Data(json.utf8))
        #expect(settings.blockTrackers)
        #expect(settings.javaScript)
        #expect(settings.pageZoom == ProfileSettings.zoomRange.upperBound)
        #expect(settings.customUserAgent == nil)
        #expect(settings.hostRules == HostRules())
    }
}
