import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let launchedFromCLI: Bool
    private var workspace: Workspace?
    private var server: ControlServer?
    private var background: BackgroundController?
    private var settingsWindow: NSWindow?
    private let settingsRoute = SettingsRoute()
    private static let terminationGrace = Duration.seconds(2)

    init(launchedFromCLI: Bool) {
        self.launchedFromCLI = launchedFromCLI
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let workspace = try Workspace()
            let router = CommandRouter(workspace: workspace)
            let server = try ControlServer { [router] in await router.handle($0, output: $1) }
            self.workspace = workspace
            self.server = server
            background = BackgroundController(workspace: workspace)
            NSApp.mainMenu?.item(withTitle: "Profiles")?.submenu?.delegate = self
            if launchedFromCLI {
                workspace.setBackground(workspace.isBackground)
            } else {
                workspace.setBackground(false)
                openDefault()
            }
        } catch {
            NSAlert(error: error).runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let workspace else { return .terminateNow }
        Task {
            await workspace.flushHistory()
            await awaitingAtMost(Self.terminationGrace) { await workspace.saveSessionCookies() }
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        workspace?.saveTabs()
        server?.stop()
        try? ControlPath.removeCaptures()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if workspace?.isBackground == true {
            workspace?.setBackground(false)
        } else if !flag {
            openDefault()
        }
        return true
    }

    @objc func toggleBackground(_ sender: Any?) {
        guard let workspace else { return }
        workspace.setBackground(!workspace.isBackground)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(toggleBackground(_:)) {
            item.state = workspace?.isBackground == true ? .on : .off
        }
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let workspace else { return }
        ProfileMenu.populate(menu, names: workspace.profileNames, current: workspace.activeSession?.name, shortcuts: true)
    }

    @objc func openProfile(_ sender: NSMenuItem) {
        guard let workspace, let name = sender.representedObject as? String else { return }
        run { try await workspace.open(name) }
    }

    @objc func deleteProfile(_ sender: NSMenuItem) {
        guard let workspace, let name = sender.representedObject as? String, workspace.confirmDeletion(of: name) else { return }
        run { try await workspace.deleteKeepingWindowOpen(name) }
    }

    @objc func newWindow(_ sender: Any?) {
        guard let workspace, let name = ProfilePrompt.ask(existing: workspace.profileNames) else { return }
        run { try await workspace.open(name) }
    }

    private func openDefault() {
        guard let workspace else { return }
        run { try await workspace.openDefault() }
    }

    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        Task {
            do {
                try await operation()
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    @objc func manageProfiles(_ sender: Any?) {
        settingsRoute.tab = .profiles
        showSettings(sender)
    }

    @objc func showSettings(_ sender: Any?) {
        guard let workspace else { return }
        let window = settingsWindow ?? makeSettingsWindow(workspace: workspace)
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func makeSettingsWindow(workspace: Workspace) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(workspace: workspace, route: settingsRoute)))
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    @objc func burnEverything(_ sender: Any?) {
        guard let workspace, BurnConfirmation.confirm() else { return }
        run {
            try await workspace.burnEverything()
            try await workspace.openDefault()
        }
    }
}
