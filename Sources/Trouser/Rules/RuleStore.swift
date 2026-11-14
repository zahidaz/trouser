import Foundation
import Observation

@MainActor
@Observable
final class RuleStore {
    private(set) var rules: ProfileRules
    private(set) var loadError: String?
    private(set) var saveError: String?
    @ObservationIgnored private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            rules = ProfileRules()
            return
        }
        do {
            rules = try JSONDecoder().decode(ProfileRules.self, from: Data(contentsOf: fileURL))
        } catch {
            rules = ProfileRules()
            loadError = error.localizedDescription
        }
    }

    var isReadable: Bool {
        loadError == nil
    }

    func update(_ change: (inout ProfileRules) -> Void) {
        var rules = rules
        change(&rules)
        save(rules)
    }

    func reset() {
        save(ProfileRules())
    }

    private func save(_ rules: ProfileRules) {
        self.rules = rules
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(rules).write(to: fileURL, options: .atomic)
            loadError = nil
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }
}
