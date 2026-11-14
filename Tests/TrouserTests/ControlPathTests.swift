import Foundation
import Testing
@testable import Trouser

struct ControlPathTests {
    @Test func removesEveryCaptureOfOneProfile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("captures-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = FileManager.default
        try manager.createDirectory(at: directory.appendingPathComponent("maps.source"), withIntermediateDirectories: true)
        for name in ["maps.png", "maps.live.jpg", "maps.html", "maps2.png", "other.png"] {
            try Data().write(to: directory.appendingPathComponent(name))
        }
        try ControlPath.removeCaptures(for: "maps", in: directory)
        #expect(try manager.contentsOfDirectory(atPath: directory.path).sorted() == ["maps2.png", "other.png"])
    }

    @Test func ignoresAMissingDirectory() throws {
        try ControlPath.removeCaptures(for: "maps", in: FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString)"))
    }
}
