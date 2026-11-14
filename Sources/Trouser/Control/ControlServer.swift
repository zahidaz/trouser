import Foundation

final class ControlServer: Sendable {
    typealias Handler = @MainActor @Sendable ([String], Output) async -> Response

    private let handler: Handler
    private let listener: UnixSocket
    private let path: String

    init(path: String = ControlPath.socket, handler: @escaping Handler) throws {
        self.handler = handler
        self.path = path
        listener = try UnixSocket.listen(at: path)
        let loop: @Sendable () -> Void = { [self] in acceptConnections() }
        Thread.detachNewThread(loop)
    }

    func stop() {
        listener.close()
        unlink(path)
    }

    private func acceptConnections() {
        while let connection = listener.accept() {
            let handler: @Sendable () -> Void = { [self] in serve(connection) }
            Thread.detachNewThread(handler)
        }
    }

    private func serve(_ connection: UnixSocket) {
        guard let request = try? connection.readLine(),
              let arguments = try? JSONDecoder().decode([String].self, from: request) else {
            connection.close()
            return
        }
        let writes = DispatchQueue(label: "trouser.connection")
        let finished = DispatchSemaphore(value: 0)
        let send: @Sendable (Frame) -> Void = { frame in
            writes.async { try? connection.writeLine(JSONEncoder().encode(frame)) }
        }
        let output = Output { send(.output($0)) }
        let work: @MainActor @Sendable () async -> Void = { [handler] in
            send(.response(await handler(arguments, output)))
            writes.async {
                connection.shutdown()
                finished.signal()
            }
        }
        let task = Task { @MainActor in await work() }
        connection.waitForHangUp()
        task.cancel()
        finished.wait()
        connection.close()
    }
}
