import Security
import WebKit

@MainActor
final class PageObserver {
    private var observations: [NSKeyValueObservation] = []
    private var progressStep = -1
    private let emit: (EventType, [String: String]) -> Void

    init(webView: WKWebView, emit: @escaping (EventType, [String: String]) -> Void) {
        self.emit = emit
        observations = [
            observe(webView, \.title) { webView in
                webView.title.flatMap { $0.isEmpty ? nil : (EventType.pageTitle, ["title": $0]) }
            },
            observe(webView, \.url) { webView in
                webView.url.map { (EventType.pageURL, ["url": $0.absoluteString]) }
            },
            observe(webView, \.hasOnlySecureContent) { webView in
                webView.url == nil ? nil : (.pageSecure, ["secure": "\(webView.hasOnlySecureContent)"])
            },
            observe(webView, \.cameraCaptureState) { webView in (.pageCapture, Self.capture(webView)) },
            observe(webView, \.microphoneCaptureState) { webView in (.pageCapture, Self.capture(webView)) },
            observe(webView, \.estimatedProgress) { [weak self] webView in self?.progress(webView.estimatedProgress) }
        ]
    }

    static func certificate(of webView: WKWebView) -> [String: String]? {
        guard let trust = webView.serverTrust,
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first else { return nil }
        var fields = ["subject": commonName(leaf) ?? "unknown"]
        fields["issuer"] = chain.dropFirst().first.flatMap(commonName) ?? fields["subject"]
        fields["host"] = webView.url?.host()
        return fields
    }

    private func progress(_ value: Double) -> (EventType, [String: String])? {
        let step = Int(value * 10)
        guard step != progressStep else { return nil }
        progressStep = step
        return (.pageProgress, ["progress": "\(step * 10)%"])
    }

    private func observe<Value>(
        _ webView: WKWebView,
        _ keyPath: KeyPath<WKWebView, Value>,
        _ event: @escaping @MainActor (WKWebView) -> (EventType, [String: String])?
    ) -> NSKeyValueObservation {
        webView.observe(keyPath, options: [.new]) { [weak self] webView, _ in
            MainActor.assumeIsolated {
                guard let self, let (type, fields) = event(webView) else { return }
                self.emit(type, fields)
            }
        }
    }

    private static func capture(_ webView: WKWebView) -> [String: String] {
        ["camera": describe(webView.cameraCaptureState), "microphone": describe(webView.microphoneCaptureState)]
    }

    private static func describe(_ state: WKMediaCaptureState) -> String {
        switch state {
        case .active: "active"
        case .muted: "muted"
        default: "off"
        }
    }

    private static func commonName(_ certificate: SecCertificate) -> String? {
        var name: CFString?
        guard SecCertificateCopyCommonName(certificate, &name) == errSecSuccess else { return nil }
        return name as String?
    }
}
