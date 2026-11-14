import Foundation
import Testing
@testable import Trouser

struct WireTests {
    @Test func encodesFrames() throws {
        let output = String(data: try JSONEncoder().encode(Frame.output("line")), encoding: .utf8)
        #expect(output == #"{"output":"line"}"#)
        let response = try JSONEncoder().encode(Frame.response(.success("done")))
        #expect(try JSONDecoder().decode(Response.self, from: response) == .success("done"))
    }

    @Test func decodesFramesAndOneShotResponses() throws {
        #expect(try JSONDecoder().decode(Frame.self, from: Data(#"{"output":"a\nb"}"#.utf8)) == .output("a\nb"))
        let legacy = Data(#"{"ok":false,"message":"no"}"#.utf8)
        #expect(try JSONDecoder().decode(Frame.self, from: legacy) == .response(.failure("no")))
        let withFile = Data(#"{"ok":true,"message":"saved","file":"/tmp/a.png"}"#.utf8)
        #expect(try JSONDecoder().decode(Frame.self, from: withFile) == .response(Response(ok: true, message: "saved", file: "/tmp/a.png")))
    }
}

@MainActor
struct RoundTripTests {
    private let path = NSTemporaryDirectory() + "trouser-test-\(UUID().uuidString.prefix(8)).sock"

    @Test func streamsLinesBeforeTheResponse() async throws {
        let server = try ControlServer(path: path) { arguments, output in
            for word in arguments {
                output(word.uppercased())
            }
            return .success("echoed \(arguments.count)")
        }
        defer { server.stop() }
        let path = path
        let (lines, response) = try await Task.detached {
            let socket = try UnixSocket.connect(to: path)
            defer { socket.close() }
            var lines: [String] = []
            let response = try ControlClient.exchange(["a", "b", "c"], over: socket) { lines.append($0) }
            return (lines, response)
        }.value
        #expect(lines == ["A", "B", "C"])
        #expect(response == .success("echoed 3"))
    }

    @Test func keepsServingAfterClientsThatLeaveAtOnce() async throws {
        let server = try ControlServer(path: path) { arguments, _ in .success("echoed \(arguments.count)") }
        defer { server.stop() }
        let path = path
        let response = try await Task.detached {
            for _ in 0..<100 {
                try UnixSocket.connect(to: path).close()
            }
            let socket = try UnixSocket.connect(to: path)
            defer { socket.close() }
            return try ControlClient.exchange(["a"], over: socket) { _ in }
        }.value
        #expect(response == .success("echoed 1"))
    }

    @Test func listeningCreatesTheMissingSocketDirectory() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("trouser-test-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: directory) }
        let nested = directory.appendingPathComponent("tmp/trouser.sock").path
        let listener = try UnixSocket.listen(at: nested)
        defer { listener.close() }
        try UnixSocket.connect(to: nested).close()
    }

    @Test func acceptingSurvivesPassingErrorsOnly() {
        #expect(UnixSocket.passes(ECONNABORTED))
        #expect(UnixSocket.passes(EINTR))
        #expect(!UnixSocket.passes(EBADF))
        #expect(!UnixSocket.passes(EINVAL))
    }

    @Test func cancelsHandlerWhenClientHangsUp() async throws {
        let cancelled = Lines()
        let server = try ControlServer(path: path) { _, output in
            output("started")
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(20))
            }
            cancelled.append("cancelled")
            return .success("")
        }
        defer { server.stop() }
        let path = path
        try await Task.detached {
            let socket = try UnixSocket.connect(to: path)
            try socket.writeLine(JSONEncoder().encode(["watch"]))
            _ = try socket.readLine()
            socket.close()
        }.value
        let deadline = ContinuousClock.now + .seconds(5)
        while cancelled.values.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(cancelled.values == ["cancelled"])
    }

    @Test func watchesWorkspaceEventsThroughTheRouter() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("trouser-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = try Workspace(profiles: ProfileStore(directory: directory))
        let router = CommandRouter(workspace: workspace)
        let server = try ControlServer(path: path) { [router] in await router.handle($0, output: $1) }
        defer { server.stop() }
        let bus = workspace.events(for: Workspace.defaultProfile)
        bus.emit(.pageTitle, ["title": "Before"])

        let path = path
        let client = Task.detached {
            let socket = try UnixSocket.connect(to: path)
            defer { socket.close() }
            var lines: [String] = []
            let response = try ControlClient.exchange(["watch", "--since", "0", "--types", "page,ui", "--count", "3"], over: socket) { lines.append($0) }
            return (lines, response)
        }
        bus.emit(.cookiesChanged, ["count": "1"])
        bus.emit(.tabOpened, tab: 1)
        bus.emit(.pageURL, tab: 1, ["url": "https://a.dev"])
        bus.emit(.pageTitle, tab: 1, ["title": "Never printed"])
        let (lines, response) = try await client.value
        #expect(response.ok)
        #expect(lines.count == 3)
        #expect(lines[0].contains("default page.title title=Before"))
        #expect(lines[1].contains("default[1] ui.tab.opened"))
        #expect(lines[2].contains("page.url url=https://a.dev"))

        let status = try await Task.detached {
            let socket = try UnixSocket.connect(to: path)
            defer { socket.close() }
            return try ControlClient.exchange(["status"], over: socket) { _ in }
        }.value
        #expect(status.message.hasPrefix("trouser: active"))
    }
}

struct FileLimitTests {
    @Test func raisesTheOpenFileLimitForManyTunnels() {
        #expect(FileLimit.raise() >= 4096)
    }
}
