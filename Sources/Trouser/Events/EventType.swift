enum EventType: String, Codable, CaseIterable, Sendable {
    case navigationStarted = "navigation.started"
    case navigationRedirected = "navigation.redirected"
    case navigationCommitted = "navigation.committed"
    case navigationFinished = "navigation.finished"
    case navigationFailed = "navigation.failed"
    case navigationResponse = "navigation.response"

    case pageTitle = "page.title"
    case pageURL = "page.url"
    case pageProgress = "page.progress"
    case pageSecure = "page.secure"
    case pageCertificate = "page.certificate"
    case pageCapture = "page.capture"
    case pagePrecise = "page.precise"

    case formFocus = "form.focus"
    case formChange = "form.change"
    case formSubmit = "form.submit"

    case netRequest = "net.request"
    case netResponse = "net.response"
    case netFinished = "net.finished"
    case netFailed = "net.failed"

    case popup = "ui.popup"
    case tabOpened = "ui.tab.opened"
    case tabClosed = "ui.tab.closed"
    case tabSelected = "ui.tab.selected"
    case dialogShown = "ui.dialog.shown"
    case dialogAnswered = "ui.dialog.answered"
    case pickerShown = "ui.picker.shown"
    case pickerClosed = "ui.picker.closed"
    case processTerminated = "ui.process.terminated"
    case processReloaded = "ui.process.reloaded"

    case downloadStarted = "download.started"
    case downloadProgress = "download.progress"
    case downloadFinished = "download.finished"
    case downloadFailed = "download.failed"

    case cookiesChanged = "cookies.changed"

    case actionRequested = "automation.requested"
    case actionPending = "automation.pending"
    case actionGranted = "automation.granted"
    case actionDenied = "automation.denied"
    case actionBlocked = "automation.blocked"
    case actionDone = "automation.done"
    case actionFailed = "automation.failed"
    case pauseChanged = "automation.paused"
    case backgroundChanged = "automation.background"

    var category: String {
        String(rawValue.prefix { $0 != "." })
    }

    var isPageReaction: Bool {
        switch self {
        case .cookiesChanged, .downloadProgress: false
        default: category != "automation"
        }
    }

    func matches(_ pattern: String) -> Bool {
        rawValue == pattern || rawValue.hasPrefix(pattern + ".")
    }

    static func isKnown(_ pattern: String) -> Bool {
        allCases.contains { $0.matches(pattern) }
    }

    static var categories: [String] {
        allCases.map(\.category).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }
}
