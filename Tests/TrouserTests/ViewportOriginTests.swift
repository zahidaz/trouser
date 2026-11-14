import QuartzCore
import Testing
@testable import Trouser

struct ViewportOriginTests {
    private func layer(_ name: String?, at position: CGPoint = .zero, _ sublayers: [CALayer] = []) -> CALayer {
        let layer = CALayer()
        layer.name = name
        layer.position = position
        sublayers.forEach(layer.addSublayer)
        return layer
    }

    @Test func readsTheMainFrameScrollFromTheScrolledContentsLayer() {
        let frame = layer("frame scrolled contents", at: CGPoint(x: -20, y: -400), [layer("frame scrolled contents", at: CGPoint(x: 0, y: -90))])
        let root = layer(nil, [layer("drawing area root", [layer("frame clipping", [layer("content", [frame])])])])
        #expect(ViewportOrigin.read(from: root) == CGPoint(x: 20, y: 400))
    }

    @Test func prefersTheShallowestScrolledContentsLayer() {
        let inner = layer("frame scrolled contents", at: CGPoint(x: 0, y: -90))
        let main = layer("frame scrolled contents", at: CGPoint(x: 0, y: -1500))
        let root = layer(nil, [layer("a", [layer("b", [layer("c", [inner])])]), layer("d", [main])])
        #expect(ViewportOrigin.read(from: root) == CGPoint(x: 0, y: 1500))
    }

    @Test func isUnknownWithoutAScrolledContentsLayer() {
        #expect(ViewportOrigin.read(from: layer(nil, [layer("hosted")])) == nil)
    }

    @Test func listsTheMainAndInnerScrollPositions() {
        let container = layer("scroll container")
        container.bounds = CGRect(x: 0, y: 400, width: 300, height: 200)
        let root = layer(nil, [layer("frame scrolled contents", at: CGPoint(x: 0, y: -1500), [layer("content", [container])])])
        #expect(ViewportOrigin.scrollPositions(in: root) == [CGPoint(x: 0, y: 1500), CGPoint(x: 0, y: 400)])
        #expect(ViewportOrigin.scrollPositions(in: layer(nil)) == [])
    }
}
