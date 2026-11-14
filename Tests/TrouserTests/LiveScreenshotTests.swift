import Foundation
import Testing
@testable import Trouser

@MainActor
struct LiveScreenshotTests {
    let start = ContinuousClock.now
    let idle: Duration = .seconds(5)

    @Test func capturesFirstTime() {
        #expect(LiveScreenshot.isDue(now: start, lastCapture: nil, lastActivity: nil, idleRefresh: idle))
    }

    @Test func capturesAfterActivity() {
        #expect(LiveScreenshot.isDue(now: start + .seconds(1), lastCapture: start, lastActivity: start + .milliseconds(500), idleRefresh: idle))
    }

    @Test func skipsWhenQuiet() {
        #expect(!LiveScreenshot.isDue(now: start + .seconds(2), lastCapture: start, lastActivity: start - .seconds(1), idleRefresh: idle))
    }

    @Test func refreshesWhenIdleLongEnough() {
        #expect(LiveScreenshot.isDue(now: start + idle, lastCapture: start, lastActivity: nil, idleRefresh: idle))
    }
}

struct LiveCommandTests {
    @Test func defaultsToOneSecond() throws {
        #expect(try Command(arguments: ["screenshot", "--live"]) == .live(profile: nil, every: .seconds(1)))
    }

    @Test func parsesInterval() throws {
        #expect(try Command(arguments: ["-p", "maps", "screenshot", "--live", "--every", "0.5"]) == .live(profile: "maps", every: .milliseconds(500)))
    }

    @Test func rejectsBadIntervals() {
        for arguments in [["screenshot", "--live", "--every"], ["screenshot", "--live", "--every", "0.05"], ["screenshot", "--live", "--every", "fast"], ["screenshot", "--live", "now"], ["screenshot", "--full", "--live"]] {
            #expect(throws: CommandError.self) { try Command(arguments: arguments) }
        }
    }

    @Test func cannotRunInsideRun() {
        #expect(throws: CommandError.self) { try Command(arguments: ["run", "screenshot", "--live"]) }
    }

    @Test func settingDefaultsOff() throws {
        #expect(!ProfileSettings().liveScreenshot)
        let decoded = try JSONDecoder().decode(ProfileSettings.self, from: Data("{}".utf8))
        #expect(!decoded.liveScreenshot)
    }
}
