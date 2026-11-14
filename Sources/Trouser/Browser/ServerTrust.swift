import Foundation
import Security

@MainActor
enum ServerTrust {
    static func evaluate(_ trust: SecTrust) async -> Bool {
        await withCheckedContinuation { continuation in
            SecTrustEvaluateAsyncWithError(trust, .main) { _, trusted, _ in
                continuation.resume(returning: trusted)
            }
        }
    }

    static func chain(of trust: SecTrust) -> [CertificateSummary] {
        let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate] ?? []
        return certificates.compactMap { CertificateDER.summary(of: SecCertificateCopyData($0) as Data) }
    }
}
