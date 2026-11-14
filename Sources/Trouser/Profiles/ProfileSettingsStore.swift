import Foundation
import Observation

@MainActor
@Observable
final class ProfileSettingsStore {
    let profile: String
    var settings: ProfileSettings {
        didSet {
            guard settings != oldValue else { return }
            save()
        }
    }
    @ObservationIgnored private let fileURL: URL

    init(profile: String, fileURL: URL) {
        self.profile = profile
        self.fileURL = fileURL
        settings = (try? JSONDecoder().decode(ProfileSettings.self, from: Data(contentsOf: fileURL))) ?? ProfileSettings()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(settings).write(to: fileURL, options: .atomic)
    }
}
