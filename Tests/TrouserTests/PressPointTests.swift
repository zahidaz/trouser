import Foundation
import Testing
@testable import Trouser

@MainActor
struct PressPointTests {
    let element: ModelElement = {
        var element = ModelElement(role: .button, label: "Canada – English", frame: CGRect(x: 100, y: 100, width: 200, height: 40), source: .dom)
        element.id = "e1"
        return element
    }()

    func hit(_ label: String?) -> PreciseHitReply {
        PreciseHitReply(hit: label.map { PreciseHit(role: "AXLink", label: $0) })
    }

    @Test func pressesTheCenterWhenItHitsTheElement() async {
        var tested: [CGPoint] = []
        let point = await PageModelStore.pressPoint(for: element) { tested.append($0); return hit("Canada – English") }
        #expect(point == CGPoint(x: 200, y: 120))
        #expect(tested.count == 1)
    }

    @Test func triesTheInsetWhenSomethingCoversTheCenter() async {
        var tested: [CGPoint] = []
        let point = await PageModelStore.pressPoint(for: element) { point in
            tested.append(point)
            return hit(tested.count == 1 ? "Cookie banner" : "Canada – English")
        }
        #expect(point == CGPoint(x: 108, y: 120))
        #expect(tested.count == 2)
    }

    @Test func stopsHitTestingAfterThePageDoesNotAnswer() async {
        var tested = 0
        let point = await PageModelStore.pressPoint(for: element) { _ in tested += 1; return nil }
        #expect(point == CGPoint(x: 200, y: 120))
        #expect(tested == 1)
    }

    @Test func fallsBackToTheCenterWhenNoPointHitsTheElement() async {
        var tested = 0
        let point = await PageModelStore.pressPoint(for: element) { _ in tested += 1; return hit(nil) }
        #expect(point == CGPoint(x: 200, y: 120))
        #expect(tested == 3)
    }
}
