import Foundation

enum SafariIdentity {
    static var applicationName: String {
        let version = Bundle(path: "/Applications/Safari.app")?
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "26.0"
        return "Version/\(version) Safari/605.1.15"
    }
}
