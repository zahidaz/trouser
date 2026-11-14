import Foundation
import Testing
@testable import Trouser

@MainActor
struct StandInTests {
    func element(_ id: String, _ role: ElementRole, _ label: String, at y: CGFloat?) -> ModelElement {
        var element = ModelElement(role: role, label: label, frame: y.map { CGRect(x: 0, y: $0, width: 40, height: 20) }, source: .dom)
        element.id = id
        return element
    }

    @Test func pressesTheVisibleLabelOfAHiddenRadio() {
        let radio = element("e1", .radio, "SmallQuick and straightforward tasks", at: nil)
        let elements = [radio, element("e2", .text, "Small", at: 100), element("e3", .text, "Quick and straightforward tasks", at: 120)]
        #expect(ElementActions.standIn(for: radio, among: elements)?.id == "e2")
    }

    @Test func ignoresBracketsAroundLabels() {
        let radio = element("e1", .radio, "[3 to 6 months]", at: nil)
        #expect(ElementActions.standIn(for: radio, among: [radio, element("e2", .text, "3 to 6 months", at: 50)])?.id == "e2")
    }

    @Test func prefersTheLongestMatchingLabel() {
        let radio = element("e1", .radio, "Less than 1 month", at: nil)
        let elements = [element("e2", .text, "Less", at: 10), element("e3", .text, "Less than 1 month", at: 40)]
        #expect(ElementActions.standIn(for: radio, among: elements)?.id == "e3")
    }

    @Test func needsAVisibleMatch() {
        let radio = element("e1", .radio, "Entry", at: nil)
        #expect(ElementActions.standIn(for: radio, among: [radio, element("e2", .text, "Entry", at: nil), element("e3", .text, "Expert", at: 30)]) == nil)
        #expect(ElementActions.standIn(for: element("e4", .radio, "", at: nil), among: [element("e5", .text, "Entry", at: 0)]) == nil)
    }

    @Test func neverCutsANumberShort() {
        let edit = element("e1", .button, "Edit 18", at: nil)
        #expect(ElementActions.standIn(for: edit, among: [edit, element("e2", .button, "Edit 1", at: 50)]) == nil)
    }
}
