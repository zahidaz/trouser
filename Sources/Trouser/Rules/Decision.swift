import Foundation

struct ActionContext: Equatable, Sendable {
    var host: String?
    var label: String?
}

struct Decision: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case paused, unreadableRules, global
        case site(HostPattern)
        case protected(LabelPattern)
    }

    let mode: Mode
    let source: Source

    var protection: LabelPattern? {
        if case .protected(let pattern) = source { return pattern }
        return nil
    }

    var refusal: String {
        switch source {
        case .paused: "paused"
        case .unreadableRules: "blocked: this profile's rules file is unreadable; fix it in Settings"
        case .global, .protected: "blocked by rule"
        case .site(let pattern): "blocked by site rule \(pattern)"
        }
    }
}

extension ActionKind {
    var isProtectable: Bool {
        self == .pointer || self == .keyboard
    }
}

extension ProfileRules {
    func decision(for kind: ActionKind, context: ActionContext, global: Mode, paused: Bool) -> Decision {
        if paused { return Decision(mode: .block, source: .paused) }
        let site = sites(matching: context.host).first { $0.actions[kind] != nil }
        let base = site.flatMap { rule in rule.actions[kind].map { Decision(mode: $0, source: .site(rule.pattern)) } }
            ?? Decision(mode: global, source: .global)
        guard kind.isProtectable, base.mode != .block, let protection = protection(for: context.label) else { return base }
        return Decision(mode: .ask, source: .protected(protection))
    }
}
