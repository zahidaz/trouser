import Foundation
import Testing
@testable import Trouser

struct ModelQueryTests {
    private let elements = ElementRegistry().assign([
        ModelElement(role: .textbox, label: "App name", value: "Trouser", frame: CGRect(x: 0, y: 0, width: 10, height: 10), source: .dom),
        ModelElement(role: .button, label: "Save as draft", states: [.disabled], frame: CGRect(x: 0, y: 20, width: 10, height: 10), source: .dom),
        ModelElement(role: .button, label: "Save", source: .dom),
        ModelElement(role: .checkbox, label: "Contains ads", states: [.checked], source: .dom),
        ModelElement(role: .text, label: "Draft saved", frame: CGRect(x: 0, y: 40, width: 10, height: 10), source: .text)
    ])

    private func labels(_ arguments: [String]) throws -> [String] {
        try ModelQuery(arguments: arguments).select(from: elements).map(\.label)
    }

    @Test func parsesRolesStatesAndQuotedText() throws {
        let query = try ModelQuery(arguments: ["button \"Save as draft\""])
        #expect(query.roles == [.button])
        #expect(query.text == "Save as draft")
        let checked = try ModelQuery(arguments: ["checked"])
        #expect(checked.states == [.checked])
        #expect(checked.text == nil)
    }

    @Test func shellGroupedArgumentsAreLiteralText() throws {
        let query = try ModelQuery(arguments: ["textbox", "App name"])
        #expect(query.roles == [.textbox])
        #expect(query.text == "App name")
        #expect(try ModelQuery(arguments: ["“checked”"]).text == "checked")
    }

    @Test func matchesByRoleAndRanksExactLabelsFirst() throws {
        #expect(try labels(["button", "Save"]) == ["Save", "Save as draft"])
        #expect(try labels(["button"]) == ["Save as draft", "Save"])
        #expect(try labels(["textbox \"App name\""]) == ["App name"])
    }

    @Test func matchesStatesNegationVisibilityAndIds() throws {
        #expect(try labels(["checked"]) == ["Contains ads"])
        #expect(try labels(["button", "!disabled"]) == ["Save"])
        #expect(try labels(["enabled", "button"]) == ["Save"])
        #expect(try labels(["visible", "button"]) == ["Save as draft"])
        #expect(try labels(["e1"]) == ["App name"])
    }

    @Test func textMatchesLabelsAndValues() throws {
        #expect(try labels(["text", "saved"]) == ["Draft saved"])
        #expect(try labels(["trouser"]) == ["App name"])
    }

    @Test func rejectsEmptyQueries() {
        #expect(throws: CommandError.usage) { try ModelQuery(arguments: []) }
        #expect(throws: CommandError.usage) { try ModelQuery(arguments: ["\"\""]) }
    }
}
