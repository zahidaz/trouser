import Foundation

struct ProfileSettings: Codable, Equatable, Sendable {
    enum ContentMode: String, Codable, CaseIterable, Identifiable, Sendable {
        case recommended, desktop, mobile

        var id: Self { self }
    }

    enum InactiveScheduling: String, Codable, CaseIterable, Identifiable, Sendable {
        case suspend, throttle, none

        var id: Self { self }
    }

    struct Viewport: Codable, Equatable, Sendable {
        var width: Int
        var height: Int

        static let standard = Viewport(width: 1280, height: 800)
        static let range = 320...3840
    }

    var javaScript = true
    var lockdownMode = false
    var contentMode = ContentMode.recommended
    var userAgent = ""
    var pageZoom = 1.0
    var viewport: Viewport?
    var inactiveScheduling = InactiveScheduling.suspend
    var blockImages = false
    var blockFonts = false
    var blockTrackers = false
    var blockedDomains: [String] = []
    var hiddenSelectors: [String] = []
    var allowedHosts: [String] = []
    var blockedHosts: [String] = []
    var preciseMode = false
    var liveScreenshot = false

    static let zoomRange = 0.5...3.0

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ProfileSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) throws -> T {
            try container.decodeIfPresent(T.self, forKey: key) ?? fallback
        }
        javaScript = try value(.javaScript, defaults.javaScript)
        lockdownMode = try value(.lockdownMode, defaults.lockdownMode)
        contentMode = try value(.contentMode, defaults.contentMode)
        userAgent = try value(.userAgent, defaults.userAgent)
        pageZoom = min(max(try value(.pageZoom, defaults.pageZoom), Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        viewport = try container.decodeIfPresent(Viewport.self, forKey: .viewport)
        inactiveScheduling = try value(.inactiveScheduling, defaults.inactiveScheduling)
        blockImages = try value(.blockImages, defaults.blockImages)
        blockFonts = try value(.blockFonts, defaults.blockFonts)
        blockTrackers = try value(.blockTrackers, defaults.blockTrackers)
        blockedDomains = try value(.blockedDomains, defaults.blockedDomains)
        hiddenSelectors = try value(.hiddenSelectors, defaults.hiddenSelectors)
        allowedHosts = try value(.allowedHosts, defaults.allowedHosts)
        blockedHosts = try value(.blockedHosts, defaults.blockedHosts)
        preciseMode = try value(.preciseMode, defaults.preciseMode)
        liveScreenshot = try value(.liveScreenshot, defaults.liveScreenshot)
    }

    var hostRules: HostRules {
        HostRules(allowed: allowedHosts, blocked: blockedHosts)
    }

    var customUserAgent: String? {
        let trimmed = userAgent.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
