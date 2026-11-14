import Foundation
import Testing
@testable import Trouser

struct PageModelTests {
    private func element(_ role: ElementRole, _ label: String, value: String? = nil, y: CGFloat? = 100, states: [ElementState] = []) -> ModelElement {
        Fixture.element(role, label, value: value, y: y, states: states)
    }

    private func model(_ elements: [ModelElement], title: String = "Listing", focus: String? = nil) -> PageModel {
        Fixture.model(elements, title: title, focus: focus)
    }

    @Test func idsStayStableWhileThePageUpdates() {
        let registry = ElementRegistry()
        let first = registry.assign([element(.textbox, "App name", value: "A"), element(.button, "Save"), element(.button, "Save")])
        let second = registry.assign([
            element(.text, "Saved"),
            element(.button, "Save", states: [.disabled]),
            element(.textbox, "App name", value: "B"),
            element(.button, "Save")
        ])
        #expect(first.map(\.id) == ["e1", "e2", "e3"])
        #expect(second.map(\.id) == ["e4", "e2", "e1", "e3"])
    }

    @Test func idsIgnoreCaseAndWhitespaceInLabels() {
        let registry = ElementRegistry()
        let first = registry.assign([element(.link, "Learn  more")])
        let second = registry.assign([element(.link, "learn more")])
        #expect(first[0].id == second[0].id)
    }

    @Test func diffReportsAddedRemovedAndChangedElements() {
        let registry = ElementRegistry()
        let old = model(registry.assign([element(.textbox, "App name", value: "A"), element(.text, "Draft"), element(.button, "Next", y: 500)]))
        let new = model(
            registry.assign([element(.textbox, "App name", value: "B"), element(.text, "Saved"), element(.button, "Next", y: 520)]),
            title: "Saved listing",
            focus: "e1"
        )
        let diff = ModelDiff(from: old, to: new)
        #expect(diff.added.map(\.label) == ["Saved"])
        #expect(diff.removed.map(\.label) == ["Draft"])
        #expect(diff.changed.map(\.fields) == [[.value], [.frame]])
        #expect(diff.page == ["title “Listing” → “Saved listing”", "focus none → e1"])
        #expect(diff.description.contains("value “A” → “B”"))
        #expect(diff.description.contains("1 element moved"))
    }

    @Test func diffOfIdenticalModelsIsEmpty() {
        let elements = ElementRegistry().assign([element(.button, "Next")])
        let diff = ModelDiff(from: model(elements), to: model(elements))
        #expect(diff.isEmpty)
        #expect(diff.description == "no changes")
    }

    @Test func diffNoticesVisibilityAndStates() {
        let registry = ElementRegistry()
        let old = model(registry.assign([element(.button, "Save", states: [.disabled]), element(.link, "Help")]))
        let new = model(registry.assign([element(.button, "Save"), element(.link, "Help", y: nil)]))
        #expect(ModelDiff(from: old, to: new).changed.map(\.fields) == [[.states], [.visible]])
    }

    @Test func textDescriptionIsOneLinePerElement() {
        let elements = ElementRegistry().assign([
            element(.button, "Save as draft", states: [.disabled]),
            element(.textbox, "App name", value: "Trouser"),
            element(.button, "Upload icon", y: nil)
        ])
        #expect(elements[0].description == "e1   button    “Save as draft”  50,110  disabled")
        #expect(elements[1].description == "e2   textbox   “App name” = “Trouser”  50,110")
        #expect(elements[2].description == "e3   button    “Upload icon”  unplaced")
    }

    @Test func jsonSchemaIsStable() throws {
        let elements = ElementRegistry().assign([element(.button, "Next", states: [.disabled]), element(.image, "Logo", y: nil)])
        let json = try model(elements, focus: "e1").json()
        let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect(object["schema"] as? Int == 1)
        #expect(object["focus"] as? String == "e1")
        let page = try #require(object["page"] as? [String: Any])
        #expect(Set(page.keys) == ["url", "title", "loading", "progress", "secure", "onlySecureContent", "generation", "viewport", "precise", "placed"])
        let items = try #require(object["elements"] as? [[String: Any]])
        #expect(Set(items[0].keys) == ["id", "role", "label", "value", "placeholder", "states", "frame", "center", "visible", "source", "url", "context"])
        #expect(items[0]["states"] as? [String] == ["disabled"])
        #expect((items[0]["center"] as? [String: Int]) == ["x": 50, "y": 110])
        #expect(items[1]["frame"] is NSNull)
        #expect(items[1]["visible"] as? Bool == false)
    }
}
