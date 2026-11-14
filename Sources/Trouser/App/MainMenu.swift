import AppKit

@MainActor
enum MainMenu {
    static func make() -> NSMenu {
        let windowMenu = submenu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
            .separator(),
            item("Show Previous Tab", #selector(NSWindow.selectPreviousTab(_:)), "\t", [.control, .shift]),
            item("Show Next Tab", #selector(NSWindow.selectNextTab(_:)), "\t", [.control]),
            item("Move Tab to New Window", #selector(NSWindow.moveTabToNewWindow(_:))),
            item("Merge All Windows", #selector(NSWindow.mergeAllWindows(_:))),
            .separator(),
            item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)))
        ])
        NSApp.windowsMenu = windowMenu.submenu

        let menu = NSMenu()
        [
            submenu("Trouser", [
                item("About Trouser", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
                .separator(),
                item("Settings…", #selector(AppDelegate.showSettings(_:)), ","),
                .separator(),
                item("Burn Everything…", #selector(AppDelegate.burnEverything(_:)), "\u{8}", [.command, .shift]),
                .separator(),
                item("Hide Trouser", #selector(NSApplication.hide(_:)), "h"),
                item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
                item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
                .separator(),
                item("Quit Trouser", #selector(NSApplication.terminate(_:)), "q")
            ]),
            submenu("File", [
                item("New Tab", #selector(NSResponder.newWindowForTab(_:)), "t"),
                item("New Window…", #selector(AppDelegate.newWindow(_:)), "n"),
                item("Open Location", #selector(BrowserWindowController.focusAddressBar(_:)), "l"),
                .separator(),
                item("Close Tab", #selector(NSWindow.performClose(_:)), "w")
            ]),
            submenu("Edit", [
                item("Undo", Selector(("undo:")), "z"),
                item("Redo", Selector(("redo:")), "z", [.command, .shift]),
                .separator(),
                item("Cut", #selector(NSText.cut(_:)), "x"),
                item("Copy", #selector(NSText.copy(_:)), "c"),
                item("Paste", #selector(NSText.paste(_:)), "v"),
                item("Select All", #selector(NSText.selectAll(_:)), "a")
            ]),
            submenu("View", [
                item("Reload Page", #selector(BrowserWindowController.reload(_:)), "r"),
                item("Show Sidebar", #selector(NSSplitViewController.toggleSidebar(_:)), "l", [.command, .shift]),
                item("Show Automation", #selector(NSSplitViewController.toggleInspector(_:)), "i", [.command, .option]),
                item("Send to Background", #selector(AppDelegate.toggleBackground(_:)), "b", [.command, .option]),
                .separator(),
                item("Show Tab Bar", #selector(NSWindow.toggleTabBar(_:))),
                item("Show All Tabs", #selector(NSWindow.toggleTabOverview(_:)), "\\", [.command, .shift]),
                item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])
            ]),
            submenu("Profiles", []),
            submenu("History", [
                item("Back", #selector(BrowserWindowController.goBack(_:)), "["),
                item("Forward", #selector(BrowserWindowController.goForward(_:)), "]"),
                item("Start Page", #selector(BrowserWindowController.showStartPage(_:)), "h", [.command, .shift])
            ]),
            windowMenu
        ].forEach(menu.addItem)
        return menu
    }

    private static func item(
        _ title: String,
        _ action: Selector,
        _ key: String = "",
        _ modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem()
        let submenu = NSMenu(title: title)
        items.forEach(submenu.addItem)
        item.submenu = submenu
        return item
    }
}
