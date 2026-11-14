import AppKit

final class AddressField: NSSearchField {
    private static let reloadLabel = "Reload Page"

    var url: URL? {
        didSet { if currentEditor() == nil { showSummary() } }
    }

    init() {
        super.init(frame: .zero)
        placeholderString = "Search or enter website name"
        sendsWholeSearchString = true
        sendsSearchStringImmediately = false
        maximumRecents = 0
        lineBreakMode = .byTruncatingTail
        font = .systemFont(ofSize: NSFont.systemFontSize + 1)
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        widthAnchor.constraint(greaterThanOrEqualToConstant: 360).isActive = true
        widthAnchor.constraint(lessThanOrEqualToConstant: 820).isActive = true
        showReload()
        showSummary()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        alignment = .left
        stringValue = url?.absoluteString ?? ""
        Task { @MainActor [weak self] in
            self?.currentEditor()?.selectAll(nil)
        }
        return true
    }

    override func cancelOperation(_ sender: Any?) {
        window?.makeFirstResponder(nil)
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        showSummary()
    }

    override func layout() {
        super.layout()
        removeAllToolTips()
        guard let cell = cell as? NSSearchFieldCell else { return }
        addToolTip(cell.cancelButtonRect(forBounds: bounds), owner: Self.reloadLabel as NSString, userData: nil)
    }

    private func showReload() {
        guard let button = (cell as? NSSearchFieldCell)?.cancelButtonCell else { return }
        let image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: Self.reloadLabel)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: NSFont.systemFontSize, weight: .medium))
        button.image = image
        button.alternateImage = image
        button.setAccessibilityLabel(Self.reloadLabel)
        button.target = nil
        button.action = #selector(BrowserWindowController.reload(_:))
    }

    private func showSummary() {
        alignment = url == nil ? .left : .center
        let host = url?.host().map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? ""
        stringValue = url?.scheme == "http" ? "Not Secure — \(host)" : host
    }
}
