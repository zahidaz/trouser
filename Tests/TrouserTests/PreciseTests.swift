import Foundation
import Testing
import WebKit
@testable import Trouser

struct PreciseMessageTests {
    @Test func decodesNetworkEvents() {
        #expect(PreciseEvent(json: #"{"v":1,"type":"net.willSend","id":13,"method":"POST","url":"https://a.example/x","redirect":false}"#)
            == .request(method: "POST", url: "https://a.example/x", redirect: false))
        #expect(PreciseEvent(json: #"{"v":1,"type":"net.response","id":13,"url":"https://a.example/x","status":404,"mime":"text/html"}"#)
            == .response(url: "https://a.example/x", status: 404, mime: "text/html"))
        #expect(PreciseEvent(json: #"{"v":1,"type":"net.finish","id":13,"url":"https://a.example/x"}"#) == .finished(url: "https://a.example/x"))
        #expect(PreciseEvent(json: #"{"v":1,"type":"net.fail","id":13,"url":"u","error":"offline"}"#) == .failed(url: "u", error: "offline"))
    }

    @Test func decodesLoadFormAndHelloEvents() {
        #expect(PreciseEvent(json: #"{"v":1,"type":"hello","version":1}"#) == .hello(version: 1))
        #expect(PreciseEvent(json: #"{"v":2,"type":"hello","version":2}"#) == .hello(version: 2))
        #expect(PreciseEvent(json: #"{"v":1,"type":"load.commit","frame":"main","url":"u"}"#) == .load("commit", main: true))
        #expect(PreciseEvent(json: #"{"v":1,"type":"load.finish","frame":"sub","url":"u"}"#) == .load("finish", main: false))
        #expect(PreciseEvent(json: #"{"v":1,"type":"form.focus","frame":[24,162,660,38],"kind":"field"}"#) == .focus(CGRect(x: 24, y: 162, width: 660, height: 38)))
        #expect(PreciseEvent(json: #"{"v":1,"type":"form.change","frame":[24,334,658,90],"kind":"area"}"#) == .change(CGRect(x: 24, y: 334, width: 658, height: 90), area: true))
        #expect(PreciseEvent(json: #"{"v":1,"type":"form.submit","fields":3}"#) == .submit(fields: 3))
    }

    @Test func rejectsUnknownAndForeignVersions() {
        #expect(PreciseEvent(json: #"{"v":1,"type":"something.else"}"#) == nil)
        #expect(PreciseEvent(json: #"{"v":2,"type":"net.finish","url":"u"}"#) == nil)
        #expect(PreciseEvent(json: "not json") == nil)
    }

    @Test func encodesCommands() {
        #expect(PreciseCommand.snapshot.json == #"{"command":"snapshot","v":1}"#)
        #expect(PreciseCommand.hitTest(CGPoint(x: 106, y: 459)).json == #"{"command":"hitTest","v":1,"x":106,"y":459}"#)
    }
}

struct PreciseSnapshotTests {
    private let base = PreciseSnapshot(revision: 4, nodes: [
        PreciseNode(key: "n1", role: "AXHeading", title: "Title"),
        PreciseNode(key: "n2", role: "AXTextField", title: "Name", value: "Old"),
        PreciseNode(key: "n3", role: "AXButton", title: "Save")
    ])

    @Test func appliesPushedChanges() throws {
        let json = #"{"v":1,"type":"dom.changes","base":4,"revision":5,"upsert":[{"key":"n2","role":"AXTextField","title":"Name","value":"New"},{"key":"n4","role":"AXStaticText","value":"Saved"}],"remove":["n3"],"order":["n1","n2","n4"]}"#
        guard case .changes(let changes) = PreciseEvent(json: json) else {
            Issue.record("not a change event")
            return
        }
        let applied = try #require(base.applying(changes))
        #expect(applied.revision == 5)
        #expect(applied.nodes.map(\.key) == ["n1", "n2", "n4"])
        #expect(applied.nodes[1].value == "New")
    }

    @Test func appendsNewNodesWhenOrderIsUnchanged() throws {
        let changes = PreciseChanges(base: 4, revision: 5, upsert: [PreciseNode(key: "n2", role: "AXTextField", title: "Name", value: "Typed")], remove: [], order: nil)
        let applied = try #require(base.applying(changes))
        #expect(applied.nodes.map(\.key) == ["n1", "n2", "n3"])
        #expect(applied.nodes[1].value == "Typed")
    }

    @Test func refusesChangesFromAnotherRevision() {
        let changes = PreciseChanges(base: 3, revision: 4, upsert: [], remove: ["n1"], order: nil)
        #expect(base.applying(changes) == nil)
    }

    @Test func findsTheControlAtAFormFieldFrame() {
        let snapshot = PreciseSnapshot(revision: 1, nodes: [
            PreciseNode(key: "n1", role: "AXStaticText", value: "Name", frame: [24, 162, 660, 38]),
            PreciseNode(key: "n2", role: "AXTextField", title: "Name", frame: [24, 162, 660, 38])
        ])
        #expect(snapshot.node(at: CGRect(x: 24, y: 162.4, width: 660, height: 38))?.key == "n2")
        #expect(snapshot.node(at: CGRect(x: 0, y: 0, width: 10, height: 10)) == nil)
    }
}

struct PreciseMappingTests {
    private let viewport = CGSize(width: 1000, height: 760)

    private func fixture() throws -> PreciseSnapshot {
        let json = #"""
        {"v":1,"revision":3,"nodes":[
          {"key":"n1","role":"AXHeading","title":"Main store listing","frame":[16,9,254,38]},
          {"key":"n2","role":"AXStaticText","parent":"n1","value":"Main store listing","frame":[16,9,254,38]},
          {"key":"n3","role":"AXStaticText","value":"App name","frame":[24,138,74,18]},
          {"key":"n4","role":"AXTextField","dom":"name","title":"App name","value":"Hello Precise","required":true,"focused":true,"frame":[24,162,660,38]},
          {"key":"n5","role":"AXTextField","dom":"short","title":"Short description","placeholder":"Describe your app","frame":[24,248,660,38]},
          {"key":"n6","role":"AXButton","title":"Upload icon","description":"Upload icon","frame":[92,450,28,18]},
          {"key":"n7","role":"AXPopUpButton","dom":"cat","title":"Category","value":"Productivity","frame":[24,516,640,41]},
          {"key":"n8","role":"AXCheckBox","dom":"ads","title":"Contains ads","number":1,"frame":[24,581,642,33]},
          {"key":"n9","role":"AXStaticText","value":"Contains ads","frame":[24,596,95,18]},
          {"key":"n10","role":"AXTextField","subrole":"AXSecureTextField","title":"Password","frame":[24,662,660,38]},
          {"key":"n11","role":"AXButton","title":"Save as draft","disabled":true,"frame":[850,730,86,18]},
          {"key":"n12","role":"AXLink","title":"Back to top","url":"https://example.com/#top","frame":[24,1633,83,18]},
          {"key":"n13","role":"AXStaticText","value":"Graphics far below","frame":[24,1500,120,18]},
          {"key":"n14","role":"AXStaticText","value":"  ","frame":[270,19,9,18]},
          {"key":"n15","role":"AXButton","title":"Menu","expanded":false,"frame":[900,9,40,30]},
          {"key":"n16","role":"AXRadioButton","subrole":"AXTabButton","title":"Overview","number":1,"frame":[300,60,80,30]},
          {"key":"n17","role":"AXImage","frame":[0,0,10,10]},
          {"key":"n18","role":"AXTextArea","title":"Notes","readonly":true,"invalid":true,"frame":[24,300,600,90]}
        ]}
        """#
        return try #require(PreciseMessage.decode(PreciseSnapshot.self, from: json))
    }

    private func element(_ label: String) throws -> ModelElement {
        try #require(PreciseMapping.elements(try fixture(), viewport: viewport).first { $0.label == label })
    }

    @Test func mapsControlsWithLiveValuesAndStates() throws {
        let name = try element("App name")
        #expect(name.role == .textbox)
        #expect(name.value == "Hello Precise")
        #expect(name.states == [.required])
        #expect(name.identity == "#name")
        #expect(name.center == CGPoint(x: 354, y: 181))
        #expect(try element("Short description").placeholder == "Describe your app")
        #expect(try element("Category").value == "Productivity")
        #expect(try element("Contains ads").states == [.checked])
        #expect(try element("Save as draft").states == [.disabled])
        #expect(try element("Menu").states == [.collapsed])
        #expect(try element("Overview").role == .tab)
        #expect(try element("Overview").states == [.selected])
        #expect(try element("Notes").states == [.readonly, .invalid])
    }

    @Test func placesIconOnlyButtonsAndKeepsPasswordsOut() throws {
        let icon = try element("Upload icon")
        #expect(icon.frame == CGRect(x: 92, y: 450, width: 28, height: 18))
        #expect(icon.visible)
        #expect(icon.identity == "n6")
        #expect(try element("Password").value == nil)
    }

    @Test func dropsDuplicateLabelTextAndOffscreenText() throws {
        let elements = PreciseMapping.elements(try fixture(), viewport: viewport)
        #expect(elements.filter { $0.label == "Main store listing" }.map(\.role) == [.heading])
        #expect(elements.filter { $0.label == "App name" }.map(\.role) == [.textbox])
        #expect(elements.filter { $0.label == "Contains ads" }.map(\.role) == [.checkbox])
        #expect(!elements.contains { $0.label == "Graphics far below" })
        #expect(!elements.contains { $0.role == .image })
        #expect(!elements.contains { $0.label.isEmpty && $0.role == .text })
    }

    @Test func keepsOffscreenControlsWithTheirFrames() throws {
        let back = try element("Back to top")
        #expect(back.offscreen)
        #expect(!back.visible)
        #expect(back.position == "offscreen 66,1642")
        #expect(back.url?.absoluteString == "https://example.com/#top")
    }

    @Test func listsVisibleTextsForWaiting() throws {
        let texts = PreciseMapping.texts(PreciseMapping.elements(try fixture(), viewport: viewport))
        #expect(texts.contains { $0.text == "Hello Precise" })
        #expect(texts.contains { $0.text == "Upload icon" })
        #expect(!texts.contains { $0.text == "Back to top" })
    }

    @Test func registryKeepsIdsAcrossLabelChangesAndReordering() throws {
        let registry = ElementRegistry()
        var first = try #require(PreciseMapping.element(PreciseNode(key: "n6", role: "AXButton", title: "Save", frame: [0, 0, 10, 10]), viewport: viewport))
        let other = try #require(PreciseMapping.element(PreciseNode(key: "n7", role: "AXButton", title: "Next", frame: [0, 0, 10, 10]), viewport: viewport))
        let ids = registry.assign([first, other]).map(\.id)
        first = try #require(PreciseMapping.element(PreciseNode(key: "n6", role: "AXButton", title: "Saved", frame: [0, 0, 10, 10]), viewport: viewport))
        #expect(registry.assign([other, first]).map(\.id) == [ids[1], ids[0]])
    }
}

@MainActor
struct PreciseSelectionTests {
    @Test func selectsBundleOnlyWhenEnabledAndPresent() {
        #expect(PreciseStatus.select(enabled: false, bundleExists: true, problem: nil) == .off)
        #expect(PreciseStatus.select(enabled: true, bundleExists: true, problem: nil) == .connecting)
        #expect(PreciseStatus.select(enabled: true, bundleExists: false, problem: nil) == .unavailable("the Precise mode bundle is missing from Trouser.app"))
        #expect(PreciseStatus.select(enabled: true, bundleExists: true, problem: "crashed") == .unavailable("crashed"))
    }

    @Test func fallsBackWhenTheBundleIsMissing() {
        let pool = PrecisePool(bundleURL: URL(fileURLWithPath: "/nonexistent/TrouserBundle.bundle"))
        let configuration = WKWebViewConfiguration()
        #expect(pool.attach(configuration, enabled: true, inherited: false) == .unavailable("the Precise mode bundle is missing from Trouser.app"))
        #expect(pool.attach(configuration, enabled: false, inherited: false) == .off)
        #expect(pool.attach(configuration, enabled: true, inherited: true) == .off)
    }

    @Test func stopsOfferingPreciseModeAfterAProblem() {
        let pool = PrecisePool(bundleURL: URL(fileURLWithPath: "/nonexistent"))
        pool.disable("stopped")
        #expect(pool.attach(WKWebViewConfiguration(), enabled: true, inherited: false) == .unavailable("stopped"))
    }

    @Test func reportsPerProfileState() {
        #expect(PreciseStatus.report(enabled: false, tabs: [.off]) == "off")
        #expect(PreciseStatus.report(enabled: true, tabs: [.active, .off]) == "on, 1 of 2 tabs precise")
        #expect(PreciseStatus.report(enabled: true, tabs: [.unavailable("missing")]) == "on, 0 of 1 tabs precise, unavailable: missing, using the capture model")
    }

    @Test func statusAppearsInThePageHeaderAndJSON() throws {
        let info = PageInfo(url: nil, title: "", loading: false, progress: 1, secure: false, onlySecureContent: false, generation: 1, viewport: .zero, precise: .unavailable("missing"))
        #expect(info.description.hasSuffix("precise mode unavailable (missing), capture model"))
        let model = PageModel(page: info, focus: nil, elements: [])
        #expect(try model.json().contains(#""precise":"unavailable""#))
    }
}
