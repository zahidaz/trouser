import AppKit
import SwiftUI

@MainActor
final class BackgroundController: NSObject, NSMenuDelegate {
    private let workspace: Workspace
    private var statusItem: NSStatusItem?
    private var approvals: NSPanel?

    init(workspace: Workspace) {
        self.workspace = workspace
        super.init()
        observe()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let front = item("Bring Trouser to Front", #selector(showWindows(_:)))
        front.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        menu.addItem(front)
        menu.addItem(.separator())

        for session in workspace.openSessions {
            guard let entry = session.supervisor.pendingEntry else { continue }
            let badge = entry.protection == nil ? "" : "Protected · "
            menu.addItem(withTitle: "\(badge)\(session.name): \(entry.summary)", action: nil, keyEquivalent: "")
            menu.addItem(item("Allow", #selector(allow(_:)), session.name))
            menu.addItem(item("Deny", #selector(deny(_:)), session.name))
            menu.addItem(.separator())
        }

        let paused = workspace.policy.paused
        menu.addItem(item(paused ? "Resume Automation" : "Pause Automation", #selector(togglePause(_:))))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Trouser", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func allow(_ sender: NSMenuItem) {
        session(for: sender)?.supervisor.resolve(true)
    }

    @objc private func deny(_ sender: NSMenuItem) {
        session(for: sender)?.supervisor.resolve(false)
    }

    @objc private func togglePause(_ sender: NSMenuItem) {
        workspace.setPaused(!workspace.policy.paused)
    }

    @objc private func showWindows(_ sender: NSMenuItem) {
        workspace.setBackground(false)
    }

    private func session(for item: NSMenuItem) -> ProfileSession? {
        (item.representedObject as? String).flatMap(workspace.session(for:))
    }

    private func item(_ title: String, _ action: Selector, _ profile: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = profile
        return item
    }

    private func observe() {
        withObservationTracking {
            refresh()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    private func refresh() {
        guard workspace.isBackground else {
            statusItem.map(NSStatusBar.system.removeStatusItem)
            statusItem = nil
            approvals?.orderOut(nil)
            approvals = nil
            return
        }
        let supervisors = workspace.openSessions.map(\.supervisor)
        let pending = supervisors.contains { $0.pendingEntry != nil }
        let acting = supervisors.contains { $0.isActing }

        let statusItem = statusItem ?? makeStatusItem()
        self.statusItem = statusItem
        let symbol = pending ? "exclamationmark.shield.fill" : workspace.policy.paused ? "pause.circle" : "shield.lefthalf.filled"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Trouser")
        statusItem.button?.contentTintColor = pending ? .systemOrange : acting ? .controlAccentColor : nil

        let approvals = approvals ?? makeApprovalsPanel()
        self.approvals = approvals
        approvals.ignoresMouseEvents = !pending
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.toolTip = "Trouser is running in Background Mode"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        return item
    }

    private func makeApprovalsPanel() -> NSPanel {
        let size = NSSize(width: 520, height: 480)
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let panel = NSPanel(
            contentRect: NSRect(x: screen.maxX - size.width, y: screen.maxY - size.height, width: size.width, height: size.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.canHide = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        let content = NSHostingView(rootView: PendingApprovalsView(workspace: workspace))
        content.sizingOptions = []
        panel.contentView = content
        panel.orderFrontRegardless()
        return panel
    }
}
