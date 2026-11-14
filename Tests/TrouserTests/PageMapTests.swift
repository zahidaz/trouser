import Foundation
import Testing
@testable import Trouser

struct PageMapTests {
    private func chunk(_ text: String) -> PageElement {
        PageElement(text: text, frame: CGRect(x: 0, y: 0, width: 80, height: 20), link: nil)
    }

    @Test func wholeWordMatchingSkipsLongerNumbers() {
        let elements = [chunk("Edit 18"), chunk("Edit 1 Details 1")]
        #expect(PageMap.match("Edit 1", in: elements).first?.text == "Edit 18")
        #expect(PageMap.match("Edit 1", in: elements, wholeWords: true).map(\.text) == ["Edit 1 Details 1"])
        #expect(PageMap.match("Edit 1", in: [chunk("Edit 1")], wholeWords: true).count == 1)
    }

    @Test func closestHitPrefersWholeWordsThenDistanceFromTheViewport() {
        let visible = CGRect(x: 0, y: 1000, width: 800, height: 600)
        let partial = PageMap.Hit(frame: CGRect(x: 10, y: 1100, width: 50, height: 20), whole: false)
        let far = PageMap.Hit(frame: CGRect(x: 10, y: 9000, width: 50, height: 20), whole: true)
        let near = PageMap.Hit(frame: CGRect(x: 10, y: 200, width: 50, height: 20), whole: true)
        #expect(PageMap.closest([partial, far, near], to: visible) == near)
        #expect(PageMap.closest([partial], to: visible) == partial)
        #expect(PageMap.closest([], to: visible) == nil)
    }

    @MainActor
    @Test func revealTriesTheCenterFirstThenEveryRegionOfTheViewport() {
        let anchors = PageDriver.anchors(in: CGRect(x: 0, y: 0, width: 800, height: 600))
        #expect(anchors.first == CGPoint(x: 400, y: 300))
        #expect(anchors.count == 9)
        #expect(Set(anchors.map(\.x)) == [200, 400, 600])
        #expect(Set(anchors.map(\.y)) == [150, 300, 450])
    }
}
