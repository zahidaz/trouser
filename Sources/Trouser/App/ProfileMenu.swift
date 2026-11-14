import AppKit

@MainActor
enum ProfileMenu {
    static func populate(_ menu: NSMenu, names: [String], current: String?, shortcuts: Bool) {
        menu.removeAllItems()
        for (index, name) in names.enumerated() {
            let key = shortcuts && index < 9 ? "\(index + 1)" : ""
            let item = NSMenuItem(title: name, action: #selector(AppDelegate.openProfile(_:)), keyEquivalent: key)
            item.keyEquivalentModifierMask = [.command, .option]
            item.representedObject = name
            item.state = name == current ? .on : .off
            item.image = NSImage(systemSymbolName: "person.crop.circle", accessibilityDescription: nil)
            menu.addItem(item)
        }
        if !names.isEmpty {
            menu.addItem(.separator())
        }
        menu.addItem(NSMenuItem(title: "New Profile…", action: #selector(AppDelegate.newWindow(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Manage Profiles…", action: #selector(AppDelegate.manageProfiles(_:)), keyEquivalent: ""))
        if let current, current != Workspace.defaultProfile {
            let delete = NSMenuItem(title: "Delete Profile “\(current)”…", action: #selector(AppDelegate.deleteProfile(_:)), keyEquivalent: "")
            delete.representedObject = current
            menu.addItem(delete)
        }
    }
}
