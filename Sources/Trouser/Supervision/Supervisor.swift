import Foundation
import Observation

@MainActor
@Observable
final class Supervisor {
    enum Outcome: Equatable {
        case pending, running, done, denied, blocked
        case failed(String)
    }

    struct Entry: Identifiable {
        let id = UUID()
        let date = Date()
        let kind: ActionKind
        let summary: String
        var context = ActionContext()
        var protection: LabelPattern?
        var outcome: Outcome
    }

    enum Authorization {
        case granted(Entry.ID)
        case refused(String)
    }

    let policy: Policy
    let rules: RuleStore
    let events: EventBus
    private(set) var isActing = false
    var isPrompting = false
    private(set) var entries: [Entry] = []
    private(set) var pendingID: Entry.ID?
    @ObservationIgnored private var continuation: CheckedContinuation<Bool, Never>?
    @ObservationIgnored private var violations: [String] = []

    private static let limit = 200

    init(policy: Policy, rules: RuleStore, events: EventBus) {
        self.policy = policy
        self.rules = rules
        self.events = events
    }

    var pendingEntry: Entry? {
        entries.first { $0.id == pendingID }
    }

    var isBusy: Bool {
        isActing || isPrompting || pendingID != nil
    }

    func decision(for kind: ActionKind, context: ActionContext = ActionContext()) -> Decision {
        guard rules.isReadable || policy.paused else { return Decision(mode: .block, source: .unreadableRules) }
        return rules.rules.decision(for: kind, context: context, global: policy.mode(for: kind), paused: policy.paused)
    }

    func authorize(_ kind: ActionKind, _ summary: String, context: ActionContext = ActionContext()) async -> Authorization {
        let decision = decision(for: kind, context: context)
        let id = record(Entry(kind: kind, summary: summary, context: context, protection: decision.protection, outcome: .pending))
        let fields = ["kind": kind.rawValue, "summary": summary]
        events.emit(.actionRequested, fields)
        switch decision.mode {
        case .allow:
            update(id, .running)
            events.emit(.actionGranted, fields)
            return .granted(id)
        case .block:
            update(id, .blocked)
            events.emit(.actionBlocked, fields.merging(["reason": decision.refusal]) { $1 })
            return .refused(decision.refusal)
        case .ask:
            guard pendingID == nil else {
                let reason = "another action is awaiting approval"
                update(id, .blocked)
                events.emit(.actionBlocked, fields.merging(["reason": reason]) { $1 })
                return .refused(reason)
            }
            pendingID = id
            events.emit(.actionPending, fields)
            let approved = await withCheckedContinuation { continuation = $0 }
            pendingID = nil
            update(id, approved ? .running : .denied)
            events.emit(approved ? .actionGranted : .actionDenied, fields)
            return approved ? .granted(id) : .refused("denied")
        }
    }

    func refuse(_ kind: ActionKind, _ summary: String, reason: String) {
        record(Entry(kind: kind, summary: "\(summary): \(reason)", outcome: .blocked))
        events.emit(.actionBlocked, ["kind": kind.rawValue, "summary": summary, "reason": reason])
        let violation = "\(summary): blocked: \(reason)"
        if isActing, !violations.contains(violation) {
            violations.append(violation)
        }
    }

    func beginAction() {
        violations.removeAll()
        isActing = true
    }

    func endAction() -> [String] {
        isActing = false
        defer { violations.removeAll() }
        return violations
    }

    func resolve(_ approved: Bool) {
        continuation?.resume(returning: approved)
        continuation = nil
    }

    func finish(_ id: Entry.ID, _ outcome: Outcome) {
        update(id, outcome)
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        let fields = ["kind": entry.kind.rawValue, "summary": entry.summary]
        if case .failed(let reason) = outcome {
            events.emit(.actionFailed, fields.merging(["error": reason]) { $1 })
        } else {
            events.emit(.actionDone, fields)
        }
    }

    @discardableResult
    private func record(_ entry: Entry) -> Entry.ID {
        entries.append(entry)
        if entries.count > Self.limit {
            entries.removeFirst(entries.count - Self.limit)
        }
        return entry.id
    }

    private func update(_ id: Entry.ID, _ outcome: Outcome) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].outcome = outcome
    }
}
