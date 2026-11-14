import Foundation
import Testing
@testable import Trouser

@MainActor
struct OrphanedDataStoreTests {
    let kept = UUID()
    let deleted = UUID()
    let base = URL(fileURLWithPath: "/stores", isDirectory: true)

    @Test func removesOnlyUnknownIdentifierFolders() {
        let folders = [kept, deleted].map { base.appendingPathComponent($0.uuidString.lowercased()) } + [base.appendingPathComponent("defaultStore")]
        #expect(ProfileStore.orphans(folders, keeping: [kept]) == [base.appendingPathComponent(deleted.uuidString.lowercased())])
    }
}
