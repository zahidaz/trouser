import Foundation

enum Reports {
    static func connections(_ records: [ConnectionRecord], now: Date) -> String {
        guard !records.isEmpty else { return "no connections yet" }
        let open = records.filter { $0.outcome == .open }.count
        let header = "\(records.count) connections, \(open) open"
        let rows = records.map { record in
            let traffic = record.outcome == .blocked ? "" : "\(bytes(record.bytesUp)) up  \(bytes(record.bytesDown)) down  \(seconds(record.duration(at: now)))"
            let outcome = record.error.map { "\(record.outcome.rawValue): \($0)" } ?? record.outcome.rawValue
            return [
                record.start.formatted(date: .omitted, time: .standard),
                pad("\(record.host):\(record.port)", 40),
                pad(outcome, 12),
                traffic
            ].joined(separator: "  ").trimmingCharacters(in: .whitespaces)
        }
        return ([header] + rows.map { "  \($0)" }).joined(separator: "\n")
    }

    static func hosts(_ hosts: [HostSummary]) -> String {
        guard !hosts.isEmpty else { return "no connections yet" }
        let header = [pad("host", 40), pad("conns", 6), pad("blocked", 8), pad("failed", 7), pad("up", 10), "down"].joined(separator: "  ")
        let rows = hosts.map { host in
            [
                pad(host.host, 40),
                pad(String(host.connections), 6),
                pad(String(host.blocked), 8),
                pad(String(host.failed), 7),
                pad(bytes(host.bytesUp), 10),
                bytes(host.bytesDown)
            ].joined(separator: "  ")
        }
        return ([header] + rows).joined(separator: "\n")
    }

    static func privacy(_ report: PrivacyReport) -> String {
        guard !report.sites.isEmpty else { return "no website data stored" }
        let header = "\(report.sites.count) sites with stored data, \(report.cookies) cookies"
        let rows = report.sites.map { site in
            "  \(pad(site.name, 36))  \(pad("\(site.cookies) cookies", 11))  \(site.dataTypes.joined(separator: ", "))"
        }
        return ([header] + rows).joined(separator: "\n")
    }

    static func settings(_ settings: ProfileSettings, profile: String, ruleError: String?, precise: String) -> String {
        let rules = ContentRules.rules(for: settings).count
        let lines: [(String, String)] = [
            ("profile", profile),
            ("javascript", onOff(settings.javaScript)),
            ("lockdown mode", onOff(settings.lockdownMode)),
            ("content mode", settings.contentMode.rawValue),
            ("user agent", settings.customUserAgent ?? "Safari (default)"),
            ("page zoom", "\(Int((settings.pageZoom * 100).rounded()))%"),
            ("viewport", settings.viewport.map { "\($0.width)×\($0.height)" } ?? "fills the window"),
            ("inactive tabs", settings.inactiveScheduling.rawValue),
            ("block images", onOff(settings.blockImages)),
            ("block fonts", onOff(settings.blockFonts)),
            ("block trackers", settings.blockTrackers ? "on (\(TrackerList.domains.count) domains)" : "off"),
            ("blocked domains", list(settings.blockedDomains, empty: "none")),
            ("hidden selectors", list(settings.hiddenSelectors, empty: "none")),
            ("content rules", ruleError.map { "failed: \($0)" } ?? "\(rules) active"),
            ("allowed hosts", list(settings.allowedHosts, empty: "any")),
            ("blocked hosts", list(settings.blockedHosts, empty: "none")),
            ("precise mode", precise),
            ("live screenshot", onOff(settings.liveScreenshot))
        ]
        return lines.map { "\(pad($0.0, 17))\($0.1)" }.joined(separator: "\n")
    }

    static func json<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private static func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }

    private static func seconds(_ interval: TimeInterval) -> String {
        String(format: "%.1fs", interval)
    }

    private static func onOff(_ value: Bool) -> String {
        value ? "on" : "off"
    }

    private static func list(_ values: [String], empty: String) -> String {
        values.isEmpty ? empty : values.joined(separator: ", ")
    }

    private static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text.padding(toLength: width, withPad: " ", startingAt: 0)
    }
}
