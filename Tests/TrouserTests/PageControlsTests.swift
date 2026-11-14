import Foundation
import Testing
@testable import Trouser

struct PageControlsTests {
    private let html = """
    <!DOCTYPE html><html><head><title>Listing</title></head><body>
    <header><h1>Main store listing</h1></header>
    <main>
    <app-field><simple-html-block id="app-name-label">App name</simple-html-block>
    <input id="name" aria-labelledby="app-name-label" value="My app" required></app-field>
    <label for="short">Short description</label><input id="short" placeholder="Describe it" readonly>
    <label for="full">Full description</label><textarea id="full">Long text</textarea>
    <button aria-label="Upload icon"><mat-icon>upload</mat-icon></button>
    <label for="cat">Category</label><select id="cat"><option>Games</option><option selected>Tools</option></select>
    <label><input type="checkbox" checked> Contains ads</label>
    <div role="checkbox" aria-checked="false" aria-disabled="true">Target children</div>
    <div role="tab" aria-selected="true">Overview</div>
    <div role="button" aria-expanded="false">More</div>
    <mat-checkbox class="mat-mdc-checkbox mat-mdc-checkbox-checked"><input type="checkbox" id="terms"><label for="terms">I agree</label></mat-checkbox>
    <a href="/help">Learn more</a>
    <input type="submit" value="Send">
    <input type="hidden" name="token" value="x">
    <div hidden><button>Secret</button></div>
    <img alt="App logo" src="logo.png">
    </main>
    <footer><button disabled>Save as draft</button></footer>
    </body></html>
    """

    private func controls() throws -> [DOMControl] {
        try PageControls.controls(inHTML: html, base: URL(string: "https://shop.example.com/admin/app"))
    }

    private func control(_ label: String) throws -> DOMControl {
        try #require(try controls().first { $0.label == label })
    }

    @Test func customElementsKeepTheirIdsForAriaLabelledBy() throws {
        let name = try control("App name")
        #expect(name.role == .textbox)
        #expect(name.value == "My app")
        #expect(name.states == [.required])
    }

    @Test func listsControlsInDocumentOrder() throws {
        #expect(try controls().map(\.label) == [
            "Main store listing", "App name", "Short description", "Full description", "Upload icon", "Category",
            "Contains ads", "Target children", "Overview", "More", "I agree", "Learn more", "Send", "App logo", "Save as draft"
        ])
    }

    @Test func readsLabelsValuesAndPlaceholders() throws {
        #expect(try control("Short description").placeholder == "Describe it")
        #expect(try control("Short description").states == [.readonly])
        #expect(try control("Full description").role == .textarea)
        #expect(try control("Full description").value == "Long text")
        #expect(try control("Category").value == "Tools")
        #expect(try control("Category").role == .select)
        #expect(try control("Send").role == .button)
        #expect(try control("App logo").role == .image)
        #expect(try control("Learn more").url == URL(string: "https://shop.example.com/help"))
    }

    @Test func readsStatesFromAttributes() throws {
        #expect(try control("Contains ads").states == [.checked])
        #expect(try control("Target children").states == [.disabled])
        #expect(try control("Overview").states == [.selected])
        #expect(try control("More").states == [.collapsed])
        #expect(try control("I agree").states == [.checked])
        #expect(try control("Save as draft").states == [.disabled])
    }

    @Test func iconOnlyControlsTakeTheirRowOrHeadingAsContext() throws {
        let html = """
        <h2>About you</h2><button><img src="next.svg"></button>
        <table><tr><td>Release 7</td><td><button aria-label="Edit">edit</button></td><td><a href="/r/7"><img src="x.png"></a></td></tr></table>
        """
        let controls = try PageControls.controls(inHTML: html)
        #expect(controls.map(\.label) == ["About you", "", "Edit", ""])
        #expect(controls[1].context == "About you")
        #expect(controls[2].context == "Release 7 edit")
        #expect(controls[3].role == .link)
        #expect(controls[3].context == "Release 7 edit")
    }

    @Test func readsDialogsAndAlerts() throws {
        let html = """
        <div role="dialog" aria-label="Discard changes?"><button>Discard</button></div>
        <div role="alert">Action required: verify your account</div>
        <div role="status"></div>
        """
        let controls = try PageControls.controls(inHTML: html)
        #expect(controls.map(\.role) == [.dialog, .button, .alert])
        #expect(controls[0].label == "Discard changes?")
        #expect(controls[2].label == "Action required: verify your account")
    }

    @Test func knowsWhichControlsDrawTheirLabel() throws {
        let html = """
        <a href="/" aria-label="Maps"></a>
        <h1 class="visually-hidden">Maps</h1>
        <button aria-label="Close dialog">Close</button>
        <button>Save draft</button>
        <input type="submit" value="Send">
        """
        let controls = try PageControls.controls(inHTML: html)
        #expect(controls.map(\.drawsLabel) == [false, false, false, true, true])
    }

    @Test func comboboxThatTakesTypingIsATextField() throws {
        let html = """
        <input role="combobox" aria-label="Search places">
        <textarea role="combobox" aria-label="Ask"></textarea>
        <div role="combobox" aria-label="Country"></div>
        <input type="button" role="combobox" aria-label="Pick">
        """
        let controls = try PageControls.controls(inHTML: html)
        #expect(controls.map(\.role) == [.textbox, .textarea, .select, .select])
    }

    @Test func decodesTextAsUnicodeAndDropsIconGlyphs() throws {
        let controls = try PageControls.controls(inHTML: "<button>Café</button><a href=\"/p\">Pamilya’s</a><button>\u{E866}Saved</button>")
        #expect(controls.map(\.label) == ["Café", "Pamilya’s", "Saved"])
    }

    @Test func archivesDecodeWithTheirTextEncoding() {
        let latin = WebArchive.Resource(url: nil, mimeType: "text/html", data: Data([0x43, 0x61, 0x66, 0xE9]), textEncodingName: "iso-8859-1")
        let utf8 = WebArchive.Resource(url: nil, mimeType: "text/html", data: Data("Café".utf8))
        #expect(latin.text == "Café")
        #expect(utf8.text == "Café")
    }

    @Test func neverReadsPasswordValues() throws {
        let controls = try PageControls.controls(inHTML: "<label for=\"p\">Password</label><input id=\"p\" type=\"password\" value=\"hunter2\"><label for=\"q\">PIN</label><input id=\"q\" type=\"password\">")
        #expect(controls.map(\.value) == ["••••", nil])
        #expect(controls.allSatisfy { $0.secret })
    }

    @Test func skipsHiddenControls() throws {
        #expect(try controls().contains { $0.label == "Secret" || $0.label == "token" } == false)
    }

    @Test func rewritesUnknownTagsForTidy() {
        let rewritten = PageControls.tidyable("<app-label id=\"a\">x</app-label><main><x-y/></main>")
        #expect(rewritten == "<div id=\"a\">x</div><div><div/></div>")
    }
}
