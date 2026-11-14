import WebKit

extension ProfileSettings.ContentMode {
    var webKit: WKWebpagePreferences.ContentMode? {
        switch self {
        case .recommended: nil
        case .desktop: .desktop
        case .mobile: .mobile
        }
    }
}

extension ProfileSettings.InactiveScheduling {
    var webKit: WKPreferences.InactiveSchedulingPolicy {
        switch self {
        case .suspend: .suspend
        case .throttle: .throttle
        case .none: .none
        }
    }
}
