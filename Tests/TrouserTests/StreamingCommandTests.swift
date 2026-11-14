import Foundation
import Testing
@testable import Trouser

struct StreamingCommandTests {
    @Test func parsesWatch() throws {
        #expect(try Command(arguments: ["watch"]) == .watch(profile: nil, WatchOptions()))
        #expect(try Command(arguments: ["-p", "work", "watch", "--json", "--types", "navigation,ui.tab", "--count", "5"])
            == .watch(profile: "work", WatchOptions(json: true, types: ["navigation", "ui.tab"], count: 5)))
        #expect(try Command(arguments: ["watch", "--until", "download.finished", "--since", "12"])
            == .watch(profile: nil, WatchOptions(until: "download.finished", since: 12)))
        #expect(throws: CommandError.self) { try Command(arguments: ["watch", "--types", "network"]) }
        #expect(throws: CommandError.self) { try Command(arguments: ["watch", "--count", "0"]) }
        #expect(throws: CommandError.usage) { try Command(arguments: ["watch", "--count"]) }
        #expect(throws: CommandError.usage) { try Command(arguments: ["watch", "--fast", "1"]) }
    }

    @Test func parsesWait() throws {
        #expect(try Command(arguments: ["wait", "load"]) == .wait(profile: nil, .load, timeout: .seconds(30)))
        #expect(try Command(arguments: ["wait", "idle", "--timeout", "2.5"]) == .wait(profile: nil, .idle, timeout: .milliseconds(2500)))
        #expect(try Command(arguments: ["wait", "text", "Order", "placed"]) == .wait(profile: nil, .text("Order placed"), timeout: .seconds(30)))
        #expect(try Command(arguments: ["-p", "a", "wait", "url", "/done"]) == .wait(profile: "a", .url("/done"), timeout: .seconds(30)))
        #expect(try Command(arguments: ["wait", "event", "download.finished"]) == .wait(profile: nil, .event("download.finished"), timeout: .seconds(30)))
        #expect(throws: CommandError.usage) { try Command(arguments: ["wait"]) }
        #expect(throws: CommandError.usage) { try Command(arguments: ["wait", "load", "now"]) }
        #expect(throws: CommandError.usage) { try Command(arguments: ["wait", "url"]) }
        #expect(throws: CommandError.self) { try Command(arguments: ["wait", "event", "nothing"]) }
        #expect(throws: CommandError.self) { try Command(arguments: ["wait", "load", "--timeout", "soon"]) }
    }

    @Test func parsesQuietActions() throws {
        #expect(try Command(arguments: ["click", "10", "20", "--quiet"]) == .page(profile: nil, action: .click(CGPoint(x: 10, y: 20), count: 1), options: ActionOptions(quiet: true)))
        #expect(try Command(arguments: ["key", "enter", "--quiet"]) == .page(profile: nil, action: .key(try KeyCombo(parsing: "enter")), options: ActionOptions(quiet: true)))
        #expect(throws: CommandError.self) { try Command(arguments: ["key", "enter", "--shot"]) }
        #expect(try Command(arguments: ["set", "e3", "Ada", "--quiet"]) == .page(profile: nil, action: .act(ElementCommand(id: "e3", operation: .set("Ada"))), options: ActionOptions(quiet: true)))
        #expect(throws: CommandError.self) { try Command(arguments: ["page", "--quiet"]) }
    }

    @Test func parsesRunSteps() throws {
        let command = try Command(arguments: ["-p", "work", "run", "go", "a.dev", ";", "click", "1", "2", ";", ";", "status", ";", "-p", "home", "wait", "load"])
        #expect(command == .run([
            .page(profile: "work", action: .navigate(.url(URL(string: "https://a.dev")!))),
            .page(profile: "work", action: .click(CGPoint(x: 1, y: 2), count: 1)),
            .status,
            .wait(profile: "home", .load, timeout: .seconds(30))
        ]))
        #expect(throws: CommandError.usage) { try Command(arguments: ["run"]) }
        #expect(throws: CommandError.usage) { try Command(arguments: ["run", ";"]) }
        #expect(throws: CommandError.self) { try Command(arguments: ["run", "watch"]) }
        #expect(throws: CommandError.self) { try Command(arguments: ["run", "page", ";", "fly"]) }
    }

    @Test func tokenizesScriptLines() throws {
        #expect(try RunScript.tokenize("type \"hello world\" ") == ["type", "hello world"])
        #expect(try RunScript.tokenize("click 'Save as draft'") == ["click", "Save as draft"])
        #expect(try RunScript.tokenize(#"type it\'s "a \"b\"""#) == ["type", "it's", "a \"b\""])
        #expect(try RunScript.tokenize("type ''") == ["type", ""])
        #expect(try RunScript.tokenize("   ").isEmpty)
        #expect(throws: CommandError.self) { try RunScript.tokenize("type \"open") }
    }

    @Test func expandsStandardInput() throws {
        var lines = ["go a.dev", "", "# comment", "click \"Next page\""][...]
        let expanded = try RunScript.expandingStandardInput(["-p", "w", "run", "-"]) { lines.popFirst() }
        #expect(expanded == ["-p", "w", "run", "go", "a.dev", ";", "click", "Next page"])
        #expect(try RunScript.expandingStandardInput(["type", "-"]) { nil } == ["type", "-"])
    }
}

struct WaitConditionTests {
    private func state(loading: Bool = false, url: String? = "https://shop.dev/cart", idle: SettleStep = .finish(.settled)) -> WaitCondition.State {
        WaitCondition.State(isLoading: loading, url: url.flatMap(URL.init(string:)), idle: idle)
    }

    @Test func load() {
        #expect(WaitCondition.load.holds(in: state()))
        #expect(!WaitCondition.load.holds(in: state(loading: true)))
        #expect(!WaitCondition.load.holds(in: state(url: nil)))
    }

    @Test func idle() {
        #expect(WaitCondition.idle.holds(in: state()))
        #expect(WaitCondition.idle.holds(in: state(idle: .finish(.unchanged))))
        #expect(!WaitCondition.idle.holds(in: state(idle: .finish(.limited))))
        #expect(!WaitCondition.idle.holds(in: state(idle: .wait(.milliseconds(20)))))
        #expect(!WaitCondition.idle.holds(in: state(loading: true)))
        #expect(WaitCondition.idle.recheck(after: state(idle: .wait(.milliseconds(20)))) == .milliseconds(20))
    }

    @Test func url() {
        #expect(WaitCondition.url("/CART").holds(in: state()))
        #expect(!WaitCondition.url("/checkout").holds(in: state()))
    }

    @Test func text() {
        var page = state()
        page.elements = [PageElement(text: "Order   placed!", frame: .zero, link: nil)]
        #expect(WaitCondition.text("order placed").holds(in: page))
        #expect(!WaitCondition.text("refunded").holds(in: page))
    }

    @Test func event() {
        var page = state()
        page.events = [Event(sequence: 1, date: Date(), profile: "p", tab: nil, type: .downloadFinished, fields: [:])]
        #expect(WaitCondition.event("download").holds(in: page))
        #expect(WaitCondition.event("download.finished").holds(in: page))
        #expect(!WaitCondition.event("download.failed").holds(in: page))
    }
}
