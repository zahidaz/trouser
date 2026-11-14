import Foundation
import Testing
@testable import Trouser

struct ActionReplyTests {
    private let registry = ElementRegistry()
    private let home: PageModel

    init() {
        home = Fixture.model(registry.assign([Fixture.element(.button, "Load report")]), title: "Home")
    }

    @Test func reportsNoVisibleChange() {
        let reply = ActionReply(summary: "click at (1, 2): done", page: "Home — https://a.dev/", changes: .diff(ModelDiff(from: home, to: home)))
        #expect(reply.text == "click at (1, 2): done\nHome — https://a.dev/\nno visible change")
        #expect(reply.changed == false)
        #expect(ActionReply(summary: "", page: "").changed == nil)
    }

    @Test func listsNotesThenChanges() {
        let report = Fixture.model(
            registry.assign([Fixture.element(.button, "Load report"), Fixture.element(.heading, "Report ready", y: 200)]),
            title: "Report",
            url: "https://a.dev/report"
        )
        let reply = ActionReply(
            summary: "click “Load report”: done",
            page: "Report — https://a.dev/report",
            notes: ["HTTP 500"],
            changes: .diff(ModelDiff(from: home, to: report))
        )
        let lines = reply.text.split(separator: "\n").map(String.init)
        #expect(lines[0...2] == ["click “Load report”: done", "Report — https://a.dev/report", "HTTP 500"])
        #expect(lines.contains("page  url https://shop.example.com/admin → https://a.dev/report"))
        #expect(lines.contains("page  title “Home” → “Report”"))
        #expect(lines.contains { $0.hasPrefix("+ ") && $0.contains("“Report ready”") })
    }

    @Test func capsLongDiffs() {
        let many = Fixture.model(registry.assign((1...60).map { Fixture.element(.link, "Row \($0)", y: CGFloat($0) * 10) }))
        let reply = ActionReply(summary: "go to x: done", page: "p", changes: .diff(ModelDiff(from: home, to: many)))
        #expect(reply.changeLines.count == ActionReply.lineLimit + 1)
        #expect(reply.changeLines.last == "… 22 more lines; run: trouser page --all")
    }

    @Test func quietRepliesSkipChanges() {
        #expect(ActionReply(summary: "press enter: done", page: "p").text == "press enter: done\np")
    }

    @Test func newPagesPrintTheBrief() {
        let brief = PageBrief(model: home)
        #expect(ActionReply(summary: "s", page: "p", changes: .page(brief)).changeLines == brief.lines)
    }

    @Test func prefersTheShorterBriefDelta() {
        let many = Fixture.model(registry.assign((1...10).map { Fixture.element(.text, "Row \($0)", y: CGFloat($0) * 10, source: .text) }), title: "Home")
        let delta = ["+ > e1 button “Load report”"]
        #expect(ActionReply(summary: "s", page: "p", changes: .diff(ModelDiff(from: home, to: many), brief: delta)).changeLines == delta)
        #expect(ActionReply(summary: "s", page: "p", changes: .diff(ModelDiff(from: home, to: many))).changeLines.count == 11)
    }
}

struct PageModelLookupTests {
    @Test func findsTheControlAtAPoint() {
        let model = Fixture.model([
            Fixture.element(.text, "Publish release now", y: 100, source: .text),
            Fixture.element(.button, "Publish", y: 100)
        ])
        #expect(model.element(at: CGPoint(x: 50, y: 110))?.label == "Publish")
        #expect(model.element(at: CGPoint(x: 500, y: 110)) == nil)
    }
}
