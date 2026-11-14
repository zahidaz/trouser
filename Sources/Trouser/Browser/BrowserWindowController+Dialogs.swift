import AppKit
import WebKit

extension BrowserWindowController: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo
    ) async -> [URL]? {
        guard let window else { return nil }
        emit(.pickerShown, ["multiple": "\(parameters.allowsMultipleSelection)", "directories": "\(parameters.allowsDirectories)"])
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        let chosen = await panel.beginSheetModal(for: window) == .OK ? panel.urls : nil
        emit(.pickerClosed, ["files": "\(chosen?.count ?? 0)"])
        return chosen
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo
    ) async {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = message
        _ = await answer(to: PageDialog(kind: "alert", message: message), with: alert, in: window)
        emit(.dialogAnswered, ["kind": "alert", "answer": "ok"])
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo
    ) async -> Bool {
        guard let window else { return false }
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let confirmed = await answer(to: PageDialog(kind: "confirm", message: message), with: alert, in: window) == .alertFirstButtonReturn
        emit(.dialogAnswered, ["kind": "confirm", "answer": confirmed ? "ok" : "cancel"])
        return confirmed
    }

    private func answer(to dialog: PageDialog, with alert: NSAlert, in window: NSWindow) async -> NSApplication.ModalResponse {
        let shown = PageDialog(kind: dialog.kind, message: dialog.message.count > 200 ? String(dialog.message.prefix(200)) + "…" : dialog.message)
        emit(.dialogShown, ["kind": shown.kind, "message": shown.message])
        dialogs.show(shown)
        defer { dialogs.close() }
        return await alert.beginSheetModal(for: window)
    }
}
