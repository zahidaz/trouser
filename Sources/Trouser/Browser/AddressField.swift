import AppKit

final class AddressField: NSSearchField {
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

    private func showSummary() {
        alignment = url == nil ? .left : .center
        let host = url?.host().map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? ""
        stringValue = url?.scheme == "http" ? "Not Secure — \(host)" : host
    }
}
