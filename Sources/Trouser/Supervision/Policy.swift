import Foundation
import Observation

enum ActionKind: String, CaseIterable, Identifiable, Codable, CodingKeyRepresentable, Sendable {
    case view, navigate, pointer, scroll, keyboard, submit, download

    var id: Self { self }

    var title: String { rawValue.capitalized }

    var defaultMode: Mode {
        switch self {
        case .view, .navigate, .scroll: .allow
        case .pointer, .keyboard, .submit, .download: .ask
        }
    }
}

enum Mode: String, CaseIterable, Identifiable, Codable, Sendable {
    case allow, ask, block

    var id: Self { self }

    var title: String { rawValue.capitalized }
}

@MainActor
@Observable
final class Policy {
    var paused = false
    var allowsWebInspector: Bool {
        didSet { defaults.set(allowsWebInspector, forKey: Self.webInspectorKey) }
    }
    private var modes: [ActionKind: Mode]
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        allowsWebInspector = defaults.bool(forKey: Self.webInspectorKey)
        modes = Dictionary(uniqueKeysWithValues: ActionKind.allCases.map { kind in
            (kind, defaults.string(forKey: Self.key(kind)).flatMap(Mode.init(rawValue:)) ?? kind.defaultMode)
        })
    }

    func mode(for kind: ActionKind) -> Mode {
        modes[kind] ?? kind.defaultMode
    }

    func setMode(_ mode: Mode, for kind: ActionKind) {
        modes[kind] = mode
        defaults.set(mode.rawValue, forKey: Self.key(kind))
    }

    private static let webInspectorKey = "allowsWebInspector"

    private static func key(_ kind: ActionKind) -> String {
        "policy.\(kind.rawValue)"
    }
}
