import AppKit

final class MarkerView: NSView {
    private var point: CGPoint?
    private var isPending = false

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func show(_ point: CGPoint?, pending: Bool) {
        self.point = point
        isPending = pending
        needsDisplay = true
    }

    func hide() {
        show(nil, pending: false)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let point else { return }
        let color: NSColor = isPending ? .systemOrange : .controlAccentColor
        let ring = NSBezierPath(ovalIn: NSRect(x: point.x - 14, y: point.y - 14, width: 28, height: 28))
        color.withAlphaComponent(0.25).setFill()
        ring.fill()
        color.setStroke()
        ring.lineWidth = 3
        ring.stroke()
    }
}
