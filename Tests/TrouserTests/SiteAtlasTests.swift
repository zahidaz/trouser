import Foundation
import Testing
@testable import Trouser

@MainActor
struct SiteAtlasTests {
    private func page(_ path: String, _ title: String) -> PageSignature {
        PageSignature(url: URL(string: "https://shop.example.com\(path)"), title: title)!
    }

    private var home: PageSignature { page("/console/app/4973/home", "Dashboard") }
    private var listing: PageSignature { page("/console/app/4973/listing", "Store listing") }
    private var details: PageSignature { page("/console/app/4973/listing/details", "App details") }

    @Test func signaturesKeepPathPatternsAndTitles() {
        let signature = PageSignature(url: URL(string: "http://127.0.0.1:8765/app/4973/user/a1b2c3d4e5f6/v2?q=secret#top"), title: "Inbox (12)")
        #expect(signature == PageSignature(host: "127.0.0.1:8765", path: "/app/*/user/*/v2", title: "Inbox (#)"))
        #expect(PageSignature(url: nil, title: "x") == nil)
    }

    @Test func recordsTransitionsAndAnnotatesDestinations() {
        var atlas = SiteAtlas()
        atlas.record(from: home, label: "Store listing", to: listing)
        atlas.record(from: home, label: "Store listing", to: listing)
        atlas.record(from: listing, label: "Save", to: listing)
        atlas.record(from: listing, label: "  ", to: home)
        #expect(atlas.transitions.count == 1)
        #expect(atlas.destinations(from: home) == ["store listing": "Store listing"])
        #expect(atlas.destinations(from: page("/console/app/12/home", "Dashboard")) == ["store listing": "Store listing"])
    }

    @Test func staysBounded() {
        var atlas = SiteAtlas()
        for index in 0...SiteAtlas.capacity {
            atlas.record(from: home, label: "Link \(index)", to: listing)
        }
        #expect(atlas.transitions.count == SiteAtlas.capacity)
        #expect(atlas.transitions.first?.label == "Link 1")
    }

    @Test func findsTheShortestKnownRoute() {
        var atlas = SiteAtlas()
        atlas.record(from: home, label: "Store listing", to: listing)
        atlas.record(from: listing, label: "Edit details", to: details)
        atlas.record(from: home, label: "Help", to: page("/help", "Help"))
        #expect(atlas.route(from: home, to: "app details")?.map(\.label) == ["Store listing", "Edit details"])
        #expect(atlas.route(from: home, to: "edit details")?.map(\.label) == ["Store listing", "Edit details"])
        #expect(atlas.route(from: listing, to: "store listing") == [])
        #expect(atlas.route(from: details, to: "dashboard") == nil)
    }

    @Test func persistsAndIsDeletedWithTheProfile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("trouser-atlas-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let profiles = try ProfileStore(directory: directory)
        let store = try profiles.atlas(for: "work")
        store.record(from: home, label: "Store listing", to: listing)
        #expect(try profiles.atlas(for: "work").atlas == store.atlas)
        #expect(FileManager.default.fileExists(atPath: store.fileURL.path))
        try await profiles.remove("work")
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    @Test func removeDeletesEveryKindOfProfileFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("trouser-files-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let profiles = try ProfileStore(directory: directory)
        _ = try profiles.rules(for: "work")
        _ = try profiles.history(for: "work")
        for kind in ProfileFile.allCases {
            let url = profiles.url(kind, for: "work")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: url)
        }
        try await profiles.remove("work")
        for kind in ProfileFile.allCases {
            #expect(!FileManager.default.fileExists(atPath: profiles.url(kind, for: "work").path))
        }
    }

    @Test func storageKeyIsCreatedOnceAndRemovedWithTheProfile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("trouser-key-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let profiles = try ProfileStore(directory: directory)
        let key = try profiles.storageKey(for: "work")
        #expect(key.count == 16)
        #expect(try profiles.storageKey(for: "work") == key)
        #expect(try profiles.storageKey(for: "play") != key)
        try await profiles.remove("work")
        #expect(try profiles.storageKey(for: "work") != key)
    }

    @Test func parsesGoto() throws {
        #expect(try Command(arguments: ["path", "App", "details"]) == .path(profile: nil, "App details"))
        #expect(throws: CommandError.self) { try Command(arguments: ["path"]) }
    }
}
