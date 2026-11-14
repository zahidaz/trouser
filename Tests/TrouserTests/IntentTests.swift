import Foundation
import Testing
@testable import Trouser

struct IntentTests {
    private let registry = ElementRegistry()

    private func page() -> PageModel {
        var icon = Fixture.element(.button, "", y: nil)
        icon.context = "About you"
        var account = Fixture.element(.link, "Manage account", y: 10)
        account.url = URL(string: "https://shop.example.com/admin/account")
        return Fixture.model(registry.assign([
            Fixture.element(.textbox, "App name", y: 100),
            Fixture.element(.textbox, "Short description", y: 140),
            Fixture.element(.button, "Save draft", y: 300),
            Fixture.element(.button, "Save", y: 340),
            Fixture.element(.button, "Publish", y: 380, states: [.disabled]),
            Fixture.element(.button, "Edit listing", y: 420),
            Fixture.element(.link, "Edit details", y: 460),
            icon,
            account
        ]))
    }

    @Test func parsesIntents() throws {
        #expect(try PageAction(name: "tap", arguments: ["Save", "draft"]) == .intent(Intent(target: "Save draft")))
        #expect(try PageAction(name: "set", arguments: ["App name", "My", "app"]) == .intent(Intent(target: "App name", value: "My app")))
        #expect(try PageAction(name: "set", arguments: ["Name", ""]) == .intent(Intent(target: "Name", value: "")))
        #expect(throws: CommandError.usage) { try PageAction(name: "set", arguments: ["", "x"]) }
        #expect(throws: CommandError.usage) { try PageAction(name: "tap", arguments: [" "]) }
        #expect(try Command(arguments: ["tap", "Save"]) == .page(profile: nil, action: .intent(Intent(target: "Save"))))
        #expect(Intent(target: "Save").summary == "tap “Save”")
        #expect(Intent(target: "Name", value: "Ada").summary == "set “Name” to “Ada”")
    }

    @Test func pressesTheClearlyBestMatch() throws {
        #expect(try IntentRanker.choose(Intent(target: "save"), in: page()).label == "Save")
        #expect(try IntentRanker.choose(Intent(target: "save draft button"), in: page()).label == "Save draft")
        #expect(try IntentRanker.choose(Intent(target: "about you"), in: page()).context == "About you")
        #expect(try IntentRanker.choose(Intent(target: "account"), in: page()).label == "Manage account")
    }

    @Test func setsOnlyTextFields() throws {
        #expect(try IntentRanker.choose(Intent(target: "short description", value: "Hi"), in: page()).role == .textbox)
        #expect(throws: ModelError.self) { try IntentRanker.choose(Intent(target: "save", value: "x"), in: page()) }
    }

    @Test func refusesAmbiguousIntents() {
        #expect {
            try IntentRanker.choose(Intent(target: "edit"), in: page())
        } throws: { error in
            guard case ModelError.ambiguous(_, let candidates) = error else { return false }
            return candidates.map(\.element.label) == ["Edit listing", "Edit details"]
                && error.localizedDescription.contains("label starts with “edit”")
        }
    }

    @Test func prefersTheOnScreenOneOfTwoControlsWithTheSameName() throws {
        let twins = Fixture.model(registry.assign([
            Fixture.element(.button, "Directions", y: nil),
            Fixture.element(.button, "Directions", y: 480)
        ]))
        #expect(try IntentRanker.choose(Intent(target: "directions"), in: twins).visible)
        let both = Fixture.model(ElementRegistry().assign([
            Fixture.element(.button, "Directions", y: 200),
            Fixture.element(.button, "Directions", y: 480)
        ]))
        #expect(throws: ModelError.self) { try IntentRanker.choose(Intent(target: "directions"), in: both) }
    }

    @Test func usesKnownDestinations() throws {
        let destinations = ["edit details": "Store settings"]
        #expect(try IntentRanker.choose(Intent(target: "store settings"), in: page(), destinations: destinations).label == "Edit details")
    }

    @Test func matchesLabelsMadeOfRoleWords() throws {
        let model = Fixture.model(registry.assign([Fixture.element(.button, "Menu"), Fixture.element(.link, "Help", y: 200)]))
        #expect(try IntentRanker.choose(Intent(target: "menu"), in: model).label == "Menu")
    }

    @Test func protectsTheResolvedTarget() throws {
        let rules = ProfileRules()
        let publish = try #require(page().elements.first { $0.label == "Publish" })
        let press = PageAction.act(ElementCommand(id: publish.id, operation: .tap, target: publish))
        #expect(rules.decision(for: press.kind, context: ActionContext(label: press.targetLabel), global: .allow, paused: false).mode == .ask)
        var trash = Fixture.element(.button, "")
        trash.context = "Delete build 12"
        let icon = PageAction.act(ElementCommand(id: "e1", operation: .tap, target: trash))
        #expect(rules.decision(for: icon.kind, context: ActionContext(label: icon.targetLabel), global: .allow, paused: false).mode == .ask)
    }

    @Test func penalizesDisabledControls() {
        let ranked = IntentRanker.rank(Intent(target: "publish"), in: page())
        #expect(ranked.first?.reasons.contains("disabled") == true)
    }
}
