import AppKit

enum ControlClient {
    private static let bundleIdentifier = "app.trouser.browser"

    static func run(_ arguments: [String]) -> Int32 {
        guard !arguments.isEmpty, arguments != ["help"] else {
            print(Command.usage)
            return 0
        }
        do {
            let request = try RunScript.expandingStandardInput(arguments) { Swift.readLine() }
            let socket = try connect()
            defer { socket.close() }
            let response = try exchange(request, over: socket) { write($0) }
            if !response.message.isEmpty {
                write(response.message)
            }
            if let file = response.file {
                write(file)
            }
            return response.ok ? 0 : 1
        } catch {
            FileHandle.standardError.write(Data("trouser: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }

    static func exchange(_ arguments: [String], over socket: UnixSocket, output: (String) -> Void) throws -> Response {
        try socket.writeLine(JSONEncoder().encode(arguments))
        while true {
            switch try JSONDecoder().decode(Frame.self, from: socket.readLine()) {
            case .output(let line): output(line)
            case .response(let response): return response
            }
        }
    }

    private static func write(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    private static func connect() throws -> UnixSocket {
        if let socket = try? UnixSocket.connect(to: ControlPath.socket) {
            return socket
        }
        guard ControlPath.socketOverride == nil,
              let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            throw ControlError.appUnavailable
        }
        try ControlPath.markLaunchFromCLI()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: app, configuration: configuration)
        for _ in 0..<50 {
            Thread.sleep(forTimeInterval: 0.1)
            if let socket = try? UnixSocket.connect(to: ControlPath.socket) {
                return socket
            }
        }
        throw ControlError.appUnavailable
    }
}
