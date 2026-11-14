import Testing
@testable import Trouser

struct ProfileDeleteCommandTests {
    @Test func parsesDelete() throws {
        #expect(try Command(arguments: ["profile", "delete", "maps"]) == .deleteProfile("maps"))
    }

    @Test func keepsProfileReport() throws {
        #expect(try Command(arguments: ["-p", "maps", "profile"]) == .profile(profile: "maps"))
    }

    @Test func rejectsMalformedDelete() {
        for arguments in [["profile", "delete"], ["profile", "delete", "a", "b"], ["-p", "maps", "profile", "delete", "maps"]] {
            #expect(throws: CommandError.self) { try Command(arguments: arguments) }
        }
    }

    @Test func cannotDeleteInsideRun() {
        #expect(throws: CommandError.self) { try Command(arguments: ["run", "profile", "delete", "maps"]) }
    }
}
