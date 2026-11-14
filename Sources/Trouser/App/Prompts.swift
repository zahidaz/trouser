import AppKit

@MainActor
enum ProfilePrompt {
    static func ask(existing: [String]) -> String? {
        let alert = NSAlert()
        alert.messageText = "Open Profile"
        alert.informativeText = "Pick a profile or type a new name. Each profile has its own cookies, logins and storage."
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")

        let field = NSComboBox(frame: NSRect(x: 0, y: 0, width: 260, height: 26))
        field.addItems(withObjectValues: existing)
        field.completes = true
        field.stringValue = existing.first ?? ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }
}

@MainActor
enum DeleteConfirmation {
    static func confirm(_ profile: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Delete profile “\(profile)”?"
        alert.informativeText = "Closes its tabs and permanently deletes its cookies, logins, storage and history."
        alert.addButton(withTitle: "Delete Profile").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

@MainActor
enum BurnConfirmation {
    static func confirm() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Burn everything?"
        alert.informativeText = "Closes every tab and permanently deletes cookies, logins, storage and cache for all profiles. You will need to sign in again."
        alert.addButton(withTitle: "Burn Everything").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
