import Darwin
import Foundation

struct UnixSocket: Sendable {
    let descriptor: Int32
    private static let retryDelay: useconds_t = 10_000

    static func connect(to path: String) throws -> UnixSocket {
        let socket = try make()
        guard withAddress(path, { Darwin.connect(socket.descriptor, $0, $1) }) == 0 else {
            let error = ControlError.system("connect")
            socket.close()
            throw error
        }
        return socket
    }

    static func listen(at path: String) throws -> UnixSocket {
        unlink(path)
        let socket = try make()
        guard withAddress(path, { bind(socket.descriptor, $0, $1) }) == 0,
              Darwin.listen(socket.descriptor, SOMAXCONN) == 0 else {
            let error = ControlError.system("listen on \(path)")
            socket.close()
            throw error
        }
        return socket
    }

    func accept() -> UnixSocket? {
        while true {
            let client = Darwin.accept(descriptor, nil, nil)
            if client >= 0 {
                Self.disableSigpipe(client)
                return UnixSocket(descriptor: client)
            }
            guard Self.passes(errno) else { return nil }
            usleep(Self.retryDelay)
        }
    }

    static func passes(_ code: Int32) -> Bool {
        [EINTR, ECONNABORTED, EAGAIN, EPROTO, EMFILE, ENFILE, ENOBUFS, ENOMEM].contains(code)
    }

    private func readSome(into buffer: UnsafeMutableRawPointer, count: Int) -> Int {
        while true {
            let received = read(descriptor, buffer, count)
            if received >= 0 || errno != EINTR {
                return received
            }
        }
    }

    func readLine(limit: Int = 1 << 20) throws -> Data {
        var line = Data()
        var byte: UInt8 = 0
        while readSome(into: &byte, count: 1) == 1 {
            if byte == UInt8(ascii: "\n") {
                return line
            }
            guard line.count < limit else { throw ControlError.requestTooLarge }
            line.append(byte)
        }
        throw ControlError.connectionClosed
    }

    func writeLine(_ data: Data) throws {
        let payload = data + [UInt8(ascii: "\n")]
        try payload.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = write(descriptor, buffer.baseAddress! + offset, buffer.count - offset)
                guard written > 0 else { throw ControlError.system("write") }
                offset += written
            }
        }
    }

    func waitForHangUp() {
        var buffer = [UInt8](repeating: 0, count: 256)
        while readSome(into: &buffer, count: buffer.count) > 0 {}
    }

    func shutdown() {
        Darwin.shutdown(descriptor, SHUT_RDWR)
    }

    func close() {
        Darwin.close(descriptor)
    }

    private static func make() throws -> UnixSocket {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw ControlError.system("socket") }
        disableSigpipe(descriptor)
        return UnixSocket(descriptor: descriptor)
    }

    private static func disableSigpipe(_ descriptor: Int32) {
        var enabled: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
    }

    private static func withAddress(_ path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) -> Int32) -> Int32 {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else {
            errno = ENAMETOOLONG
            return -1
        }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path.utf8) }
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                body($0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }
}
