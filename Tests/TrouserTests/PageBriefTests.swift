import Foundation
import Testing
@testable import Trouser

struct PageBriefTests {
    private let registry = ElementRegistry()

    private func listing(extra: [ModelElement] = []) -> PageModel {
        var publish = Fixture.element(.button, "Publish", x: 10, y: 400, states: [.disabled])
        publish.url = nil
        var icon = Fixture.element(.button, "", y: nil)
        icon.context = "About you"
        return Fixture.model(registry.assign([
            Fixture.element(.heading, "Store listing", y: 40),
            Fixture.element(.alert, "Action required: verify your account", y: nil),
            Fixture.element(.text, "Action required: verify your account", y: 70, source: .text),
            Fixture.element(.textbox, "App name", y: 120, states: [.required]),
            Fixture.element(.textbox, "Short description", value: "A tiny app", y: 160),
            Fixture.element(.button, "Save draft", y: 300),
            publish,
            Fixture.element(.text, "Only the account owner can publish this app", y: 440, source: .text),
            Fixture.element(.button, "Continue", y: 500),
            icon,
            Fixture.element(.link, "Home", y: 10),
            Fixture.element(.link, "Releases", x: 100, y: 10)
        ] + extra), title: "Store listing", url: "https://shop.example.com/admin/app/42/listing")
    }

    @Test func ranksBlockersActionsFieldsAndNavigation() {
        let lines = PageBrief(model: listing()).lines
        #expect(lines == [
            "Store listing — shop.example.com/admin/app/42/listing",
            "# e1 “Store listing”",
            "! e2 alert “Action required: verify your account”",
            "! e4 textbox “App name” (empty) required",
            "! e7 button “Publish” disabled — “Only the account owner can publish this app”",
            "> e6 button “Save draft”",
            "> e9 button “Continue”",
            "> e10 button “→ About you”",
            "= e5 textbox “Short description” = “A tiny app”",
            "nav: e11 “Home” · e12 “Releases”"
        ])
    }

    @Test func dialogWhoseTitleIsNotOnScreenIsNotABlocker() {
        let lines = PageBrief(model: listing(extra: [
            Fixture.element(.dialog, "Reviews are checked for spam", y: nil),
            Fixture.element(.text, "Reviews", y: 600, source: .text),
            Fixture.element(.dialog, "Discard changes?", y: nil),
            Fixture.element(.text, "Discard changes?", y: 640, source: .text)
        ])).lines
        #expect(!lines.contains { $0.contains("Reviews are checked for spam") })
        #expect(lines.contains { $0.hasPrefix("! ") && $0.contains("dialog “Discard changes?”") })
    }

    @Test func controlsOnScreenComeBeforeHiddenOnes() {
        let lines = PageBrief(model: listing(extra: [
            Fixture.element(.button, "Send feedback", y: nil),
            Fixture.element(.button, "Directions", y: 560)
        ])).lines
        let directions = lines.firstIndex { $0.contains("“Directions”") }
        let feedback = lines.firstIndex { $0.contains("“Send feedback”") }
        #expect(directions != nil && feedback != nil && directions! < feedback!)
    }

    @Test func approvalsAndDestinationsComeFromSignals() {
        let signals = PageBrief.Signals(
            approval: "tap e9 button “Continue”",
            destinations: ["continue": "Manage DIHAX"]
        )
        let lines = PageBrief(model: listing(), signals: signals).lines
        #expect(lines[2] == "! waiting for approval: “tap e9 button “Continue””")
        #expect(lines.contains("> e9 button “Continue” → Manage DIHAX"))
    }

    @Test func collapsesRepeatedControls() {
        let rows = (1...30).map { Fixture.element(.button, "Edit \($0)", y: nil) }
        let brief = PageBrief(model: listing(extra: rows))
        #expect(brief.lines.contains("> e13 button “Edit 1” (+29 similar)"))
        #expect(brief.lines.count <= 25)
    }

    @Test func deltaListsOnlyChangedLines() {
        let before = PageBrief(model: listing())
        let after = PageBrief(model: listing(extra: [Fixture.element(.button, "Discard", y: 600)]))
        #expect(after.delta(from: before) == ["+ > e13 button “Discard”"])
    }

    @Test func encodesJSON() throws {
        let json = try PageBrief(model: listing()).json()
        let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect(Set(object.keys) == ["title", "url", "loading", "headings", "blockers", "actions", "fields", "navigation", "omitted"])
        #expect((object["actions"] as? [[String: Any]])?.first?["id"] as? String == "e6")
    }
}
