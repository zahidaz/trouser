import AppKit

final class StageWindow: NSWindow {
    init(hosting view: NSView, size: CGSize) {
        let screen = NSScreen.main?.frame ?? .zero
        super.init(contentRect: NSRect(origin: screen.origin, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        canHide = false
        ignoresMouseEvents = true
        alphaValue = 0.01
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        isExcludedFromWindowsMenu = true
        collectionBehavior = [.transient, .ignoresCycle, .canJoinAllSpaces, .stationary]
        contentView = view
        orderFrontRegardless()
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
