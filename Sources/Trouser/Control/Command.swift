import Foundation

enum CommandError: LocalizedError, Equatable {
    case usage
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .usage: Command.usage
        case .invalid(let message): message
        }
    }
}

indirect enum Command: Equatable {
    case status
    case open(profile: String?, url: URL?)
    case page(profile: String?, action: PageAction, options: ActionOptions = ActionOptions())
    case downloads(profile: String?)
    case rules(profile: String?)
    case network(profile: String?, json: Bool, hosts: Bool)
    case privacy(profile: String?, json: Bool)
    case profile(profile: String?)
    case deleteProfile(String)
    case background(Bool)
    case watch(profile: String?, WatchOptions)
    case live(profile: String?, every: Duration)
    case wait(profile: String?, WaitCondition, timeout: Duration)
    case path(profile: String?, String)
    case expect(profile: String?, Expectation)
    case run([Command])

    var profile: String? {
        switch self {
        case .status, .background, .run, .deleteProfile: nil
        case .open(let profile, _), .page(let profile, _, _), .downloads(let profile), .rules(let profile),
             .network(let profile, _, _), .privacy(let profile, _), .profile(let profile),
             .watch(let profile, _), .live(let profile, _), .wait(let profile, _, _), .path(let profile, _), .expect(let profile, _): profile
        }
    }
}

struct ActionOptions: Equatable {
    var quiet = false
}
