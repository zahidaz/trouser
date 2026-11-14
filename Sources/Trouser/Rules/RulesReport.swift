import Foundation

struct RulesReport {
    let profile: String
    let paused: Bool
    let global: [ActionKind: Mode]
    let rules: ProfileRules
    let loadError: String?
    let host: String?

    var text: String {
        [header, globalSection, effectiveSection, sitesSection, protectedSection, fenceSection, pinsSection, mediaSection]
            .compactMap { $0 }
            .joined(separator: "\n\n")
    }

    private var header: String {
        var lines = [
            "rules for profile “\(profile)” (read-only; change them in Trouser › Settings)",
            "automation: \(paused ? "paused, every action is blocked" : "active")"
        ]
        if let loadError {
            lines.append("rules file unreadable, every action is blocked: \(loadError)")
        }
        return lines.joined(separator: "\n")
    }

    private var globalSection: String {
        section("global", ActionKind.allCases.map { "\(column($0.rawValue))\(mode(for: $0).rawValue)" })
    }

    private var effectiveSection: String? {
        guard let host else { return nil }
        let actions = ActionKind.allCases.map { kind in
            let decision = rules.decision(for: kind, context: ActionContext(host: host), global: mode(for: kind), paused: paused)
            return "\(column(kind.rawValue))\(column(decision.mode.rawValue, width: 7))\(source(decision.source))"
        }
        let media = MediaDevice.allCases.map { "\(column($0.rawValue))\(rules.mediaMode([$0], hosts: [host]).rawValue)" }
        return section("effective on \(host)", actions + media)
    }

    private var sitesSection: String {
        section(
            "site rules (the most specific matching pattern decides each action)",
            rules.sites.map { "\(column($0.pattern.text, width: 24))\($0.summary)" },
            empty: "none: global modes apply everywhere"
        )
    }

    private var protectedSection: String {
        section(
            "protected labels (clicks and key presses on matching targets always ask)",
            rules.protectedLabels.isEmpty ? [] : [rules.protectedLabels.map(\.text).joined(separator: ", ")],
            empty: "none"
        )
    }

    private var fenceSection: String {
        section(
            "navigation fence (automation may only navigate to these hosts)",
            rules.fence.map(\.text),
            empty: "none: automation may navigate anywhere"
        )
    }

    private var pinsSection: String {
        section(
            "certificate pins",
            rules.pins.map { "\(column($0.pattern.text, width: 24))\($0.summary)" },
            empty: "none: system trust only"
        )
    }

    private var mediaSection: String {
        let lines = rules.sites.compactMap { site -> String? in
            let modes = MediaDevice.allCases.compactMap { device in site.media[device].map { "\(device.rawValue) \($0.rawValue)" } }
            return modes.isEmpty ? nil : "\(column(site.pattern.text, width: 24))\(modes.joined(separator: ", "))"
        }
        return section("media permissions (camera and microphone are denied unless a site rule says otherwise)", lines, empty: "deny everywhere")
    }

    private func mode(for kind: ActionKind) -> Mode {
        global[kind] ?? kind.defaultMode
    }

    private func source(_ source: Decision.Source) -> String {
        switch source {
        case .paused: "paused"
        case .unreadableRules: "rules file unreadable"
        case .global: "global"
        case .site(let pattern): "site \(pattern)"
        case .protected(let pattern): "protected “\(pattern)”"
        }
    }

    private func section(_ title: String, _ lines: [String], empty: String = "") -> String {
        ([title] + (lines.isEmpty ? [empty] : lines).map { "  \($0)" }).joined(separator: "\n")
    }

    private func column(_ text: String, width: Int = 10) -> String {
        text.count >= width ? text + " " : text.padding(toLength: width, withPad: " ", startingAt: 0)
    }
}

extension RulesReport {
    @MainActor
    init(profile: String, policy: Policy, store: RuleStore, host: String?) {
        self.init(
            profile: profile,
            paused: policy.paused,
            global: Dictionary(uniqueKeysWithValues: ActionKind.allCases.map { ($0, policy.mode(for: $0)) }),
            rules: store.rules,
            loadError: store.loadError,
            host: host
        )
    }
}
