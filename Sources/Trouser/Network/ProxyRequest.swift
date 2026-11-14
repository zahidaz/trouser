import Foundation

enum ProxyRequestError: Error, Equatable {
    case malformed
    case unsupported(String)
    case tooLarge
}

struct ProxyRequest: Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case tunnel, http
    }

    let kind: Kind
    let host: String
    let port: UInt16
    let headerLength: Int
    let authorization: String?
    let upstreamHead: Data

    static let headLimit = 32 * 1024
    private static let terminator = Data("\r\n\r\n".utf8)
    private static let hopHeaders: Set<String> = ["proxy-connection", "proxy-authorization", "connection", "keep-alive"]

    static func parse(_ buffer: Data) throws(ProxyRequestError) -> ProxyRequest? {
        guard let end = buffer.range(of: terminator) else {
            if buffer.count > headLimit { throw .tooLarge }
            return nil
        }
        let headerLength = end.upperBound - buffer.startIndex
        guard headerLength <= headLimit else { throw .tooLarge }
        guard let head = String(data: buffer[buffer.startIndex..<end.lowerBound], encoding: .utf8) else { throw .malformed }
        var lines = head.components(separatedBy: "\r\n")
        let parts = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 3, parts[2].hasPrefix("HTTP/1.") else { throw .malformed }
        let headers = try lines.map(header)
        let authorization = headers.first { $0.name.lowercased() == "proxy-authorization" }?.value

        if parts[0] == "CONNECT" {
            guard let (host, port) = authority(parts[1], defaultPort: nil) else { throw .malformed }
            return ProxyRequest(kind: .tunnel, host: host, port: port, headerLength: headerLength, authorization: authorization, upstreamHead: Data())
        }

        guard let url = URLComponents(string: parts[1]), let scheme = url.scheme?.lowercased() else { throw .malformed }
        guard scheme == "http" else { throw .unsupported(scheme) }
        guard let host = url.host, !host.isEmpty else { throw .malformed }
        let port = UInt16(exactly: url.port ?? 80) ?? 80
        let path = url.percentEncodedPath.isEmpty ? "/" : url.percentEncodedPath
        let target = url.percentEncodedQuery.map { "\(path)?\($0)" } ?? path
        var forwarded = headers.filter { !hopHeaders.contains($0.name.lowercased()) }
        if !forwarded.contains(where: { $0.name.lowercased() == "host" }) {
            forwarded.insert((name: "Host", value: port == 80 ? host : "\(host):\(port)"), at: 0)
        }
        let upstream = (["\(parts[0]) \(target) \(parts[2])"] + forwarded.map { "\($0.name): \($0.value)" } + ["Connection: close", "", ""])
            .joined(separator: "\r\n")
        return ProxyRequest(
            kind: .http,
            host: HostRules.normalize(host),
            port: port,
            headerLength: headerLength,
            authorization: authorization,
            upstreamHead: Data(upstream.utf8)
        )
    }

    static func authority(_ text: String, defaultPort: UInt16?) -> (host: String, port: UInt16)? {
        let host: Substring
        let portText: Substring?
        if text.hasPrefix("[") {
            guard let close = text.firstIndex(of: "]") else { return nil }
            host = text[text.index(after: text.startIndex)..<close]
            let rest = text[text.index(after: close)...]
            guard rest.isEmpty || rest.hasPrefix(":") else { return nil }
            portText = rest.isEmpty ? nil : rest.dropFirst()
        } else {
            let pieces = text.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            host = pieces[0]
            portText = pieces.count == 2 ? pieces[1] : nil
        }
        guard !host.isEmpty, !host.contains(where: \.isWhitespace) else { return nil }
        let port = if let portText { UInt16(portText) } else { defaultPort }
        guard let port, port > 0 else { return nil }
        return (HostRules.normalize(String(host)), port)
    }

    private static func header(_ line: String) throws(ProxyRequestError) -> (name: String, value: String) {
        guard let colon = line.firstIndex(of: ":") else { throw .malformed }
        let name = String(line[..<colon])
        guard !name.isEmpty, !name.contains(where: \.isWhitespace) else { throw .malformed }
        return (name, line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces))
    }
}
