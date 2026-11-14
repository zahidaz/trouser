import Foundation
import Testing
@testable import Trouser

@MainActor
struct PolicyTests {
    private let defaults = UserDefaults(suiteName: "trouser.tests.\(UUID().uuidString)")!
    private let rules = RuleStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("trouser-policy-\(UUID().uuidString).json"))

    private func supervisor(_ policy: Policy) -> Supervisor {
        Supervisor(policy: policy, rules: rules, events: EventBus(profile: "test"))
    }

    @Test func usesDefaultModes() {
        let supervisor = supervisor(Policy(defaults: defaults))
        #expect(supervisor.decision(for: .view).mode == .allow)
        #expect(supervisor.decision(for: .pointer).mode == .ask)
        #expect(supervisor.decision(for: .submit).mode == .ask)
    }

    @Test func persistsModes() {
        Policy(defaults: defaults).setMode(.block, for: .keyboard)
        #expect(Policy(defaults: defaults).mode(for: .keyboard) == .block)
    }

    @Test func pauseBlocksEverything() {
        let policy = Policy(defaults: defaults)
        policy.paused = true
        let supervisor = supervisor(policy)
        #expect(ActionKind.allCases.allSatisfy { supervisor.decision(for: $0) == Decision(mode: .block, source: .paused) })
    }

    @Test func supervisorAppliesPolicy() async {
        let policy = Policy(defaults: defaults)
        policy.setMode(.block, for: .scroll)
        let supervisor = supervisor(policy)

        guard case .granted = await supervisor.authorize(.view, "screenshot") else {
            Issue.record("view should be allowed")
            return
        }
        guard case .refused = await supervisor.authorize(.scroll, "scroll") else {
            Issue.record("scroll should be blocked")
            return
        }
        #expect(supervisor.entries.map(\.outcome) == [.running, .blocked])
    }

    @Test func supervisorWaitsForApproval() async {
        let supervisor = supervisor(Policy(defaults: defaults))
        async let decision = supervisor.authorize(.pointer, "click")
        while supervisor.pendingEntry == nil {
            await Task.yield()
        }
        supervisor.resolve(false)
        guard case .refused("denied") = await decision else {
            Issue.record("click should be denied")
            return
        }
        #expect(supervisor.pendingEntry == nil)
    }

    @Test func refusesASecondAskWhileOneIsPending() async {
        let supervisor = supervisor(Policy(defaults: defaults))
        async let first = supervisor.authorize(.pointer, "click")
        while supervisor.pendingEntry == nil {
            await Task.yield()
        }
        let pending = supervisor.pendingID
        guard case .refused("another action is awaiting approval") = await supervisor.authorize(.submit, "submit") else {
            Issue.record("second ask should be refused")
            return
        }
        #expect(supervisor.pendingID == pending)
        supervisor.resolve(true)
        guard case .granted = await first else {
            Issue.record("first ask should still be approved")
            return
        }
        #expect(supervisor.pendingID == nil)
        #expect(supervisor.entries.map(\.outcome) == [.running, .blocked])
    }

    @Test func protectedTargetsAskAndCarryTheirLabel() async {
        let policy = Policy(defaults: defaults)
        policy.setMode(.allow, for: .pointer)
        let supervisor = supervisor(policy)
        let context = ActionContext(host: "shop.example.com", label: "Send 2 changes for review")
        async let decision = supervisor.authorize(.pointer, "click “Send 2 changes for review”", context: context)
        while supervisor.pendingEntry == nil {
            await Task.yield()
        }
        #expect(supervisor.pendingEntry?.protection?.text == "send*for review")
        #expect(supervisor.pendingEntry?.context == context)
        supervisor.resolve(true)
        guard case .granted = await decision else {
            Issue.record("approved protected click should run")
            return
        }
    }

    @Test func refusalsDuringAnActionAreReported() {
        let supervisor = supervisor(Policy(defaults: defaults))
        supervisor.refuse(.navigate, "navigate to evil.dev", reason: "outside the fence")
        supervisor.beginAction()
        supervisor.refuse(.navigate, "navigate to evil.dev", reason: "outside the fence")
        #expect(supervisor.endAction() == ["navigate to evil.dev: blocked: outside the fence"])
        #expect(supervisor.endAction().isEmpty)
        #expect(supervisor.entries.map(\.outcome) == [.blocked, .blocked])
    }
}
