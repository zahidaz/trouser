import Foundation
import WebKit

extension BrowserWindowController {
    func webView(
        _ webView: WKWebView,
        respondTo challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = space.serverTrust,
              let pin = session.supervisor.rules.rules.pin(for: space.host) else {
            return (.performDefaultHandling, nil)
        }
        guard await ServerTrust.evaluate(trust) else {
            session.supervisor.refuse(.navigate, "connect to \(space.host)", reason: "certificate is not trusted")
            return (.cancelAuthenticationChallenge, nil)
        }
        guard pin.accepts(ServerTrust.chain(of: trust)) else {
            session.supervisor.refuse(.navigate, "connect to \(space.host)", reason: "certificate does not match the pin for \(pin.pattern)")
            return (.cancelAuthenticationChallenge, nil)
        }
        return (.useCredential, URLCredential(trust: trust))
    }
}
