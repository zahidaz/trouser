import AppKit
import SwiftUI

extension NSToolbarItem.Identifier {
    static let navigation = Self("navigation")
    static let address = Self("address")
    static let reload = Self("reload")
    static let burn = Self("burn")
    static let home = Self("home")
    static let share = Self("share")
    static let downloads = Self("downloads")
    static let newTab = Self("newTab")
    static let tabOverview = Self("tabOverview")
    static let profile = Self("profile")
    static let sendToBackground = Self("sendToBackground")
}

extension BrowserWindowController: NSToolbarDelegate, NSSharingServicePickerToolbarItemDelegate, NSMenuDelegate {
    func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "browser")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.centeredItemIdentifiers = [.address]
        toolbar.allowsUserCustomization = false
        return toolbar
    }

    func updateNavigationButtons() {
        guard let group = window?.toolbar?.items.first(where: { $0.itemIdentifier == .navigation }) as? NSToolbarItemGroup,
              group.subitems.count == 2 else { return }
        group.subitems[0].isEnabled = webView.canGoBack
        group.subitems[1].isEnabled = webView.canGoForward
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleSidebar, .sidebarTrackingSeparator, .navigation,
            .flexibleSpace, .address, .reload, .flexibleSpace,
            .burn, .space, .home, .downloads, .share, .newTab, .tabOverview,
            .space, .sendToBackground, .profile,
            .inspectorTrackingSeparator, .toggleInspector
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch identifier {
        case .navigation: navigationItem()
        case .address: addressItem()
        case .reload: button(identifier, "Reload Page", "arrow.clockwise", #selector(reload(_:)), target: self)
        case .burn: button(identifier, "Burn Everything", "flame", #selector(AppDelegate.burnEverything(_:)), target: nil)
        case .home: button(identifier, "Start Page", "house", #selector(showStartPage(_:)), target: self)
        case .share: shareItem()
        case .downloads: downloadsItem()
        case .profile: profileItem()
        case .sendToBackground: button(identifier, "Send to Background", "menubar.arrow.up.rectangle", #selector(AppDelegate.toggleBackground(_:)), target: nil)
        case .newTab: button(identifier, "New Tab", "plus", #selector(newWindowForTab(_:)), target: self)
        case .tabOverview: button(identifier, "Show All Tabs", "square.on.square", #selector(NSWindow.toggleTabOverview(_:)), target: nil)
        default: nil
        }
    }

    func items(for pickerToolbarItem: NSSharingServicePickerToolbarItem) -> [Any] {
        webView.url.map { [$0] } ?? []
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        populateProfiles(menu)
    }

    private func profileItem() -> NSToolbarItem {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.bezelStyle = .toolbar
        button.menu?.delegate = self
        button.menu.map(populateProfiles)

        let item = NSToolbarItem(itemIdentifier: .profile)
        item.label = "Profile"
        item.toolTip = "Switch Profile"
        item.view = button
        return item
    }

    private func populateProfiles(_ menu: NSMenu) {
        ProfileMenu.populate(menu, names: session.profileNames(), current: session.name, shortcuts: false)
        let title = NSMenuItem(title: session.name, action: nil, keyEquivalent: "")
        title.image = NSImage(systemSymbolName: "person.crop.circle", accessibilityDescription: "Profile")
        menu.insertItem(title, at: 0)
    }

    private func downloadsItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: .downloads)
        item.label = "Downloads"
        item.toolTip = "Downloads"
        item.view = NSHostingView(rootView: DownloadsButton(downloads: session.downloads))
        return item
    }

    private func shareItem() -> NSToolbarItem {
        let item = NSSharingServicePickerToolbarItem(itemIdentifier: .share)
        item.label = "Share"
        item.delegate = self
        return item
    }

    private func navigationItem() -> NSToolbarItem {
        let images = ["chevron.left", "chevron.right"].compactMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        let group = NSToolbarItemGroup(
            itemIdentifier: .navigation,
            images: images,
            selectionMode: .momentary,
            labels: ["Back", "Forward"],
            target: self,
            action: #selector(navigate(_:))
        )
        group.label = "Back/Forward"
        group.controlRepresentation = .expanded
        group.autovalidates = false
        group.subitems.forEach { $0.isEnabled = false }
        return group
    }

    private func addressItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: .address)
        item.label = "Address"
        item.view = addressField
        item.visibilityPriority = .high
        return item
    }

    private func button(
        _ identifier: NSToolbarItem.Identifier,
        _ label: String,
        _ symbol: String,
        _ action: Selector,
        target: AnyObject?
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.toolTip = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.action = action
        item.target = target
        item.isBordered = true
        return item
    }
}
