import Foundation
import Testing
@testable import Trouser

struct CommandTests {
    @Test func parsesStatus() throws {
        #expect(try Command(arguments: ["status"]) == .status)
    }

    @Test func parsesOpenWithAndWithoutURL() throws {
        #expect(try Command(arguments: ["open"]) == .open(profile: nil, url: nil))
        #expect(try Command(arguments: ["open", "example.com"]) == .open(profile: nil, url: URL(string: "https://example.com")))
        #expect(try Command(arguments: ["-p", "play", "open"]) == .open(profile: "play", url: nil))
    }

    @Test func profileFlagIsOptional() throws {
        #expect(try Command(arguments: ["click", "10", "20"]) == .page(profile: nil, action: .click(CGPoint(x: 10, y: 20), count: 1)))
        #expect(try Command(arguments: ["drag", "10", "20", "30", "40"]) == .page(profile: nil, action: .drag(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 30, y: 40))))
        #expect(throws: CommandError.self) { try Command(arguments: ["drag", "10", "20", "30"]) }
        #expect(try Command(arguments: ["--profile", "p", "click", "10", "20", "2"]) == .page(profile: "p", action: .click(CGPoint(x: 10, y: 20), count: 2)))
    }

    @Test func parsesScreenshotsAndDownloads() throws {
        #expect(try Command(arguments: ["screenshot"]) == .page(profile: nil, action: .screenshot(fullPage: false)))
        #expect(try Command(arguments: ["screenshot", "--full"]) == .page(profile: nil, action: .screenshot(fullPage: true)))
        #expect(try Command(arguments: ["-p", "work", "downloads"]) == .downloads(profile: "work"))
        #expect(throws: CommandError.usage) { try Command(arguments: ["screenshot", "--wide"]) }
    }

    @Test func parsesBackgroundMode() throws {
        #expect(try Command(arguments: ["background", "on"]) == .background(true))
        #expect(try Command(arguments: ["background", "off"]) == .background(false))
        #expect(throws: CommandError.usage) { try Command(arguments: ["background", "maybe"]) }
    }

    @Test func parsesElementCommands() throws {
        #expect(try Command(arguments: ["source", "--all"]) == .page(profile: nil, action: .source(all: true)))
        #expect(try Command(arguments: ["show", "Save", "as", "draft"]) == .page(profile: nil, action: .find("Save as draft")))
        #expect(throws: CommandError.usage) { try Command(arguments: ["show"]) }
    }

    @Test func parsesReadOnlyRules() throws {
        #expect(try Command(arguments: ["rules"]) == .rules(profile: nil))
        #expect(try Command(arguments: ["-p", "play", "rules"]) == .rules(profile: "play"))
        #expect(throws: CommandError.usage) { try Command(arguments: ["rules", "set"]) }
    }

    @Test func navigationActionsExposeTheirDestination() throws {
        let url = try #require(URL(string: "https://a.dev"))
        #expect(PageAction.navigate(.url(url)).destination == url)
        #expect(PageAction.tab(.new(url)).destination == url)
        #expect(PageAction.navigate(.back).destination == nil)
        #expect(PageAction.tab(.new(nil)).destination == nil)
    }

    @Test func parsesModelCommands() throws {
        #expect(try Command(arguments: ["page"]) == .page(profile: nil, action: .brief(json: false)))
        #expect(try Command(arguments: ["page", "--json"]) == .page(profile: nil, action: .brief(json: true)))
        #expect(try Command(arguments: ["page", "--all"]) == .page(profile: nil, action: .state(json: false, recognizing: false)))
        #expect(try Command(arguments: ["page", "--ocr", "--json", "--all"]) == .page(profile: nil, action: .state(json: true, recognizing: true)))
        #expect(throws: CommandError.usage) { try Command(arguments: ["page", "--ocr"]) }
        #expect(throws: CommandError.usage) { try Command(arguments: ["page", "--json", "--json"]) }
        #expect(throws: CommandError.usage) { try Command(arguments: ["page", "--all", "--xml"]) }
        #expect(try PageAction(name: "query", arguments: ["button \"Save as draft\""]) == .query(try ModelQuery(arguments: ["button", "Save as draft"])))
        #expect(throws: CommandError.usage) { try Command(arguments: ["query"]) }
    }

    @Test func parsesElementActions() throws {
        guard case .act(let set) = try PageAction(name: "set", arguments: ["E17", "My", "app"]) else {
            Issue.record("expected act")
            return
        }
        #expect(set.id == "e17")
        #expect(set.operation == .set("My app"))
        #expect(set.kind == .keyboard)
        #expect(PageAction.act(set).focusedElement == "e17")
        #expect(PageAction.act(set).typedLength == 6)
        guard case .act(let press) = try PageAction(name: "tap", arguments: ["e3"]) else {
            Issue.record("expected act")
            return
        }
        #expect(press.kind == .pointer)
        #expect(PageAction.act(press).focusedElement == nil)
        #expect(PageAction.act(press).summary == "tap e3")
        guard case .act(let show) = try PageAction(name: "show", arguments: ["e3"]) else {
            Issue.record("expected act")
            return
        }
        #expect(show.kind == .scroll)
        #expect(PageAction.act(show).summary == "show e3")
        #expect(throws: CommandError.usage) { try PageAction(name: "tap", arguments: []) }
        #expect(throws: CommandError.usage) { try PageAction(name: "set", arguments: ["e3"]) }
        #expect(try PageAction(name: "tap", arguments: ["e3", "now"]) == .intent(Intent(target: "e3 now")))
    }

    @Test func parsesReadOnlyReports() throws {
        #expect(try Command(arguments: ["network"]) == .network(profile: nil, json: false, hosts: false))
        #expect(try Command(arguments: ["-p", "work", "network", "--hosts", "--json"]) == .network(profile: "work", json: true, hosts: true))
        #expect(try Command(arguments: ["privacy", "--json"]) == .privacy(profile: nil, json: true))
        #expect(try Command(arguments: ["profile"]) == .profile(profile: nil))
        #expect(throws: CommandError.usage) { try Command(arguments: ["network", "--json", "--json"]) }
        #expect(throws: CommandError.usage) { try Command(arguments: ["profile", "set", "javascript", "on"]) }
        #expect(throws: CommandError.usage) { try Command(arguments: ["privacy", "--delete"]) }
    }

    @Test func typeJoinsWords() throws {
        #expect(try Command(arguments: ["type", "hello", "world"]) == .page(profile: nil, action: .type("hello world")))
    }

    @Test func parsesNavigationAndTabs() throws {
        #expect(try PageAction(name: "go", arguments: ["back"]) == .navigate(.back))
        #expect(try PageAction(name: "go", arguments: ["https://a.dev"]) == .navigate(.url(URL(string: "https://a.dev")!)))
        #expect(try PageAction(name: "tab", arguments: ["new"]) == .tab(.new(nil)))
        #expect(try PageAction(name: "tab", arguments: ["close"]) == .tab(.close))
        #expect(try PageAction(name: "tab", arguments: ["2"]) == .tab(.select(2)))
    }

    @Test func mapsActionsToKinds() throws {
        #expect(PageAction.screenshot(fullPage: false).kind == .view)
        #expect(PageAction.source(all: true).kind == .view)
        #expect(PageAction.click(.zero, count: 1).kind == .pointer)
        #expect(PageAction.find("Save").kind == .scroll)
        #expect(PageAction.state(json: true, recognizing: false).kind == .view)
        #expect(PageAction.type("x").kind == .keyboard)
        #expect(PageAction.tab(.close).kind == .navigate)
    }

    @Test func rejectsInvalidInput() {
        #expect(throws: CommandError.usage) { try Command(arguments: []) }
        #expect(throws: CommandError.usage) { try Command(arguments: ["-p"]) }
        #expect(throws: CommandError.usage) { try Command(arguments: ["click"]) }
        #expect(throws: CommandError.usage) { try Command(arguments: ["fly"]) }
        #expect(throws: CommandError.usage) { try Command(arguments: ["view"]) }
        #expect(throws: CommandError.usage) { try Command(arguments: ["view", "--changes"]) }
        #expect(throws: CommandError.usage) { try Command(arguments: ["elements"]) }
        #expect(throws: CommandError.usage) { try Command(arguments: ["elements", "--all"]) }
        #expect(throws: CommandError.usage) { try Command(arguments: ["click", "Next"]) }
        #expect(throws: CommandError.usage) { try Command(arguments: ["act", "e3", "press"]) }
        #expect(throws: CommandError.invalid("--quiet applies to tap, set, show, click, drag, scroll, type, key, go and tab")) { try Command(arguments: ["page", "--quiet"]) }
        #expect(throws: CommandError.self) { try Command(arguments: ["click", "10", "20", "--shot"]) }
        #expect(throws: CommandError.self) { try Command(arguments: ["click", "1", "1", "4"]) }
        #expect(throws: CommandError.self) { try Command(arguments: ["tab", "0"]) }
    }
}

struct ExpectationTests {
    @Test func parsesExpectations() throws {
        #expect(try Command(arguments: ["expect", "text", "Report", "ready"]) == .expect(profile: nil, .page(.text("Report ready"))))
        #expect(try Command(arguments: ["expect", "url", "/report"]) == .expect(profile: nil, .page(.url("/report"))))
        #expect(try Command(arguments: ["expect", "no-change"]) == .expect(profile: nil, .noChange))
        for invalid in [["expect"], ["expect", "load"], ["expect", "no-change", "x"], ["expect", "text"]] {
            #expect(throws: CommandError.self) { try Command(arguments: invalid) }
        }
    }

    @Test func runsExpectationsAsSteps() throws {
        let command = try Command(arguments: ["-p", "work", "run", "tap", "Save", ";", "expect", "no-change"])
        #expect(command == .run([
            .page(profile: "work", action: .intent(Intent(target: "Save"))),
            .expect(profile: "work", .noChange)
        ]))
    }
}
