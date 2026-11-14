import AppKit
import WebKit

extension BrowserWindowController {
    func webView(
        _ webView: WKWebView,
        decideMediaCapturePermissionsFor origin: WKSecurityOrigin,
        initiatedBy frame: WKFrameInfo,
        type: WKMediaCaptureType
    ) async -> WKPermissionDecision {
        let devices = MediaDevice.devices(for: type)
        let hosts = Array(Set([origin.host, frame.securityOrigin.host]))
        let rules = session.supervisor.rules
        let mode = rules.isReadable ? rules.rules.mediaMode(devices, hosts: hosts) : .deny
        switch mode {
        case .allow: return .grant
        case .deny: return .deny
        case .ask: return await askForMedia(devices, host: origin.host) ? .grant : .deny
        }
    }

    private func askForMedia(_ devices: [MediaDevice], host: String) async -> Bool {
        let supervisor = session.supervisor
        guard !session.isBackground, !supervisor.isPrompting, let window, window.isVisible else { return false }
        supervisor.isPrompting = true
        defer { supervisor.isPrompting = false }
        let alert = NSAlert()
        alert.messageText = "Allow “\(host)” to use your \(devices.map(\.rawValue).joined(separator: " and "))?"
        alert.informativeText = "Profile “\(session.name)”. Change this for the site in Settings › Profiles › Rules."
        alert.addButton(withTitle: "Don’t Allow")
        alert.addButton(withTitle: "Allow")
        return await alert.beginSheetModal(for: window) == .alertSecondButtonReturn
    }
}

extension MediaDevice {
    static func devices(for type: WKMediaCaptureType) -> [MediaDevice] {
        switch type {
        case .camera: [.camera]
        case .microphone: [.microphone]
        case .cameraAndMicrophone: [.camera, .microphone]
        @unknown default: []
        }
    }
}
