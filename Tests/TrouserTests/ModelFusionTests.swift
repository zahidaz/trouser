import Foundation
import Testing
@testable import Trouser

struct ModelFusionTests {
    private func chunk(_ text: String, _ x: CGFloat, _ y: CGFloat, width: CGFloat = 100, link: URL? = nil) -> PageElement {
        PageElement(text: text, frame: CGRect(x: x, y: y, width: width, height: 18), link: link)
    }

    private let form = [
        PageElement(text: "Main store listing", frame: CGRect(x: 16, y: 9, width: 250, height: 38), link: nil),
        PageElement(text: "App name", frame: CGRect(x: 24, y: 137, width: 74, height: 18), link: nil),
        PageElement(text: "My Cool App", frame: CGRect(x: 34, y: 172, width: 88, height: 18), link: nil),
        PageElement(text: "Short description", frame: CGRect(x: 24, y: 223, width: 125, height: 18), link: nil),
        PageElement(text: "Describe your app", frame: CGRect(x: 34, y: 258, width: 240, height: 18), link: nil),
        PageElement(text: "Full description", frame: CGRect(x: 24, y: 309, width: 111, height: 18), link: nil),
        PageElement(text: "Save as draft", frame: CGRect(x: 1059, y: 772, width: 69, height: 13), link: nil),
        PageElement(text: "Next", frame: CGRect(x: 1155, y: 772, width: 24, height: 13), link: nil)
    ]

    private let controls = [
        DOMControl(role: .heading, label: "Main store listing"),
        DOMControl(role: .textbox, label: "App name", value: "Old value"),
        DOMControl(role: .textbox, label: "Short description", placeholder: "Describe your app"),
        DOMControl(role: .textarea, label: "Full description"),
        DOMControl(role: .button, label: "Upload icon"),
        DOMControl(role: .button, label: "Save as draft", states: [.disabled]),
        DOMControl(role: .button, label: "Next")
    ]

    private func fused() -> [ModelElement] {
        ModelFusion.elements(controls: controls, texts: form)
    }

    @Test func placesTextboxAtItsValueAndReadsItFromScreen() throws {
        let name = try #require(fused().first { $0.label == "App name" })
        #expect(name.center == CGPoint(x: 78, y: 181))
        #expect(name.value == "My Cool App")
        #expect(name.source == .dom)
    }

    @Test func placeholderTextIsNotAValue() throws {
        let short = try #require(fused().first { $0.label == "Short description" })
        #expect(short.center == CGPoint(x: 154, y: 267))
        #expect(short.value == nil)
        #expect(short.placeholder == "Describe your app")
    }

    @Test func emptyFieldFallsBackToItsLabelWithoutStealingOtherLabels() throws {
        let full = try #require(fused().first { $0.label == "Full description" })
        #expect(full.center == CGPoint(x: 80, y: 318))
        #expect(full.role == .textarea)
    }

    @Test func fieldSharingAChunkWithItsLabelIsPlacedAtItsText() throws {
        let texts = [chunk("App name Trouser", 20, 140, width: 160), chunk("Short description A tiny app", 20, 180, width: 280)]
        let controls = [
            DOMControl(role: .textbox, label: "App name"),
            DOMControl(role: .textbox, label: "Short description", value: "A tiny app")
        ]
        let elements = ModelFusion.elements(controls: controls, texts: texts)
        #expect(elements.map(\.value) == ["Trouser", "A tiny app"])
        #expect(elements.map(\.center) == [CGPoint(x: 145, y: 149), CGPoint(x: 250, y: 189)])
        #expect(elements.filter { $0.source == .text }.isEmpty)
    }

    @Test func labelFollowedByAnotherControlsLabelIsNotAField() throws {
        let texts = [chunk("Search Sign in", 20, 140)]
        let controls = [DOMControl(role: .textbox, label: "Search"), DOMControl(role: .button, label: "Sign in")]
        let search = try #require(ModelFusion.elements(controls: controls, texts: texts).first { $0.label == "Search" })
        #expect(search.value == nil)
    }

    @Test func iconOnlyButtonIsListedUnplaced() throws {
        let icon = try #require(fused().first { $0.label == "Upload icon" })
        #expect(icon.frame == nil)
        #expect(!icon.visible)
    }

    @Test func buttonsKeepStatesAndClaimTheirText() {
        let elements = fused()
        #expect(elements.first { $0.label == "Save as draft" }?.states == [.disabled])
        #expect(elements.filter { $0.source == .text }.isEmpty)
    }

    @Test func keepsUnclaimedTextAsTextElements() {
        let texts = [chunk("Graphics", 24, 600), chunk("Learn more", 24, 640, link: URL(string: "https://a.dev"))]
        let elements = ModelFusion.elements(controls: [], texts: texts)
        #expect(elements.map(\.role) == [.text, .link])
        #expect(elements.last?.url == URL(string: "https://a.dev"))
    }

    @Test func splitsPartiallyMatchedTextAroundTheControl() throws {
        let texts = [chunk("Fill in your app details. Learn more", 24, 96, width: 360)]
        let elements = ModelFusion.elements(controls: [DOMControl(role: .link, label: "Learn more")], texts: texts)
        let link = try #require(elements.first { $0.role == .link })
        #expect(link.frame?.minX == 284)
        #expect(link.frame?.width == 100)
        #expect(elements.filter { $0.source == .text }.map(\.label) == ["Fill in your app details."])
    }

    @Test func repeatedLabelsInsideOneLineTakeSuccessiveOccurrences() {
        let texts = [chunk("hide | 4 hours ago | hide", 0, 50, width: 250)]
        let controls = [DOMControl(role: .link, label: "hide"), DOMControl(role: .link, label: "hide"), DOMControl(role: .link, label: "hide")]
        let elements = ModelFusion.elements(controls: controls, texts: texts)
        #expect(elements.prefix(3).map { $0.frame?.minX } == [0, 210, nil])
        #expect(elements.dropFirst(3).map(\.label) == ["| 4 hours ago |"])
    }

    @Test func duplicateLabelsFollowDocumentOrder() {
        let texts = [chunk("Edit", 24, 100), chunk("Edit", 24, 200)]
        let controls = [DOMControl(role: .button, label: "Edit"), DOMControl(role: .button, label: "Edit"), DOMControl(role: .button, label: "Edit")]
        let elements = ModelFusion.elements(controls: controls, texts: texts)
        #expect(elements.map { $0.center?.y } == [109, 209, nil])
    }

    @Test func fieldWithoutVisibleLabelIsPlacedAtItsPlaceholder() throws {
        let texts = [chunk("Search apps", 300, 40)]
        let elements = ModelFusion.elements(controls: [DOMControl(role: .textbox, label: "Search", placeholder: "Search apps")], texts: texts)
        let search = try #require(elements.first)
        #expect(search.center == CGPoint(x: 350, y: 49))
        #expect(elements.count == 1)
    }

    @Test func recognizedTextIsDeduplicatedAgainstPDFText() {
        let texts = [chunk("Graphics", 24, 600)]
        let recognized = [chunk("Graphics", 25, 601), chunk("Canvas Revenue", 24, 700)]
        let elements = ModelFusion.elements(controls: [], texts: texts, recognized: recognized)
        #expect(elements.map(\.label) == ["Graphics", "Canvas Revenue"])
        #expect(elements.last?.source == .ocr)
    }

    @Test func readingOrderPutsUnplacedLast() {
        let elements = ModelFusion.readingOrder(fused())
        #expect(elements.first?.label == "Main store listing")
        #expect(elements.last?.label == "Upload icon")
        #expect(elements.map(\.label).firstIndex(of: "Next") == elements.count - 2)
    }

    @Test func controlLabelDoesNotClaimPartOfALongerNumberOrWord() {
        let texts = [chunk("Edit 18", 400, 56), chunk("Saved draft", 400, 90)]
        let elements = ModelFusion.elements(controls: [DOMControl(role: .button, label: "Edit 1"), DOMControl(role: .button, label: "Save")], texts: texts)
        #expect(elements.first { $0.label == "Edit 1" }?.frame == nil)
        #expect(elements.first { $0.label == "Save" }?.frame == nil)
        #expect(elements.contains { $0.label == "Edit 18" && $0.source == .text })
    }

    @Test func controlLabelStillClaimsItsPartOfALineOfAdjacentControls() {
        let controls = [DOMControl(role: .button, label: "Edit 1"), DOMControl(role: .link, label: "Details 1")]
        let elements = ModelFusion.elements(controls: controls, texts: [chunk("Edit 1 Details 1", 400, 56, width: 160)])
        #expect(elements.first { $0.label == "Edit 1" }?.frame?.minX == 400)
        #expect(elements.first { $0.label == "Details 1" }?.frame?.minX == 470)
    }

    @Test func controlLabelClaimsAPartSetOffByPunctuation() {
        let elements = ModelFusion.elements(controls: [DOMControl(role: .button, label: "Archive")], texts: [chunk("Delete · Archive", 0, 56, width: 160)])
        #expect(elements.first { $0.label == "Archive" }?.frame?.minX == 90)
        #expect(elements.contains { $0.label == "Delete ·" && $0.source == .text })
    }

    @Test func controlLabelIsNotPlacedOnASentenceThatMentionsIt() {
        let texts = [chunk("Pressed Edit 900, probe Release 4 top 279", 40, 820, width: 300), chunk("Pressed Edit 900", 40, 860)]
        let controls = [DOMControl(role: .button, label: "Edit 900"), DOMControl(role: .button, label: "Edit 900")]
        let elements = ModelFusion.elements(controls: controls, texts: texts)
        #expect(elements.filter { $0.label == "Edit 900" }.allSatisfy { $0.frame == nil })
        #expect(elements.filter { $0.source == .text }.map(\.label) == ["Pressed Edit 900, probe Release 4 top 279", "Pressed Edit 900"])
    }

    @Test func linkLabelIsStillPlacedInsideRunningText() {
        let elements = ModelFusion.elements(controls: [DOMControl(role: .link, label: "the guide")], texts: [chunk("Read the guide before you start", 0, 56, width: 310)])
        #expect(elements.first { $0.role == .link }?.frame?.minX == 50)
    }

    @Test func controlThatDoesNotDrawItsLabelLeavesTheTextToTheField() {
        let controls = [
            DOMControl(role: .link, label: "Apple Maps", drawsLabel: false),
            DOMControl(role: .heading, label: "Apple Maps", drawsLabel: false),
            DOMControl(role: .textbox, label: "Apple Maps", placeholder: "Apple Maps")
        ]
        let elements = ModelFusion.elements(controls: controls, texts: [chunk("Apple Maps", 300, 90)])
        #expect(elements.first { $0.role == .link }?.frame == nil)
        #expect(elements.first { $0.role == .heading }?.frame == nil)
        #expect(elements.first { $0.role == .textbox }?.frame?.minY == 90)
    }

    @Test func fieldLabelFallbackIgnoresAMentionInsideASentence() {
        let texts = [chunk("Enter your Email to continue", 0, 56, width: 280), chunk("Email *", 0, 100, width: 70)]
        let elements = ModelFusion.elements(controls: [DOMControl(role: .textbox, label: "Email")], texts: texts)
        #expect(elements.first { $0.role == .textbox }?.frame?.minY == 100)
    }

    @Test func wholeWordMatchingAllowsUncasedScripts() {
        #expect(TextMatch.find("保存", in: "保存する", wholeWords: true)?.match == .prefix)
        #expect(TextMatch.find("edit 1", in: "edit 18", wholeWords: true) == nil)
        #expect(TextMatch.find("edit 1", in: "edit 18")?.match == .prefix)
        #expect(TextMatch.find("save", in: "save, then close", wholeWords: true)?.match == .prefix)
    }
}
