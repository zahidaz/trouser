import TrouserBridge
import Foundation
import WebKit

@MainActor
final class PrecisePool {
    private let bundleURL: URL?
    private var pool: TrouserBundlePool?
    private var problem: String?

    init(bundleURL: URL? = Bundle.main.builtInPlugInsURL?.appendingPathComponent("TrouserBundle.bundle")) {
        self.bundleURL = bundleURL
    }

    func attach(_ configuration: WKWebViewConfiguration, enabled: Bool, inherited: Bool) -> PreciseStatus {
        if inherited {
            return pool?.isConfigured(configuration) == true ? .connecting : .off
        }
        let exists = bundleURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        let status = PreciseStatus.select(enabled: enabled, bundleExists: exists, problem: problem)
        guard status == .connecting, let bundleURL else { return status }
        let pool = pool ?? TrouserBundlePool(bundleURL: bundleURL)
        self.pool = pool
        pool.configure(configuration)
        return status
    }

    func disable(_ reason: String) {
        problem = reason
    }
}
