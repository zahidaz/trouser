import Foundation
import UniformTypeIdentifiers

struct WebArchive {
    struct Resource {
        let url: URL?
        let mimeType: String
        let data: Data
        var textEncodingName: String?

        var text: String {
            let encoding = textEncodingName
                .map { CFStringConvertIANACharSetNameToEncoding($0 as CFString) }
                .flatMap { $0 == kCFStringEncodingInvalidId ? nil : String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding($0)) }
            return encoding.flatMap { String(data: data, encoding: $0) } ?? String(decoding: data, as: UTF8.self)
        }
    }

    let main: Resource
    let resources: [Resource]

    init(data: Data) throws {
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let main = (plist["WebMainResource"] as? [String: Any]).flatMap(Self.resource) else {
            throw DriverError.captureFailed
        }
        self.main = main
        resources = Self.collect(plist)
    }

    func write(to directory: URL) throws -> URL {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let index = directory.appendingPathComponent("index.html")
        try main.data.write(to: index)
        for resource in resources {
            let file = Self.uniqueFile(for: resource, in: directory)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try resource.data.write(to: file)
        }
        return index
    }

    private static func collect(_ archive: [String: Any]) -> [Resource] {
        let subresources = (archive["WebSubresources"] as? [[String: Any]] ?? []).compactMap(resource)
        let frames = (archive["WebSubframeArchives"] as? [[String: Any]] ?? []).flatMap { frame in
            ((frame["WebMainResource"] as? [String: Any]).flatMap(resource).map { [$0] } ?? []) + collect(frame)
        }
        return subresources + frames
    }

    private static func resource(_ dictionary: [String: Any]) -> Resource? {
        guard let data = dictionary["WebResourceData"] as? Data else { return nil }
        return Resource(
            url: (dictionary["WebResourceURL"] as? String).flatMap(URL.init(string:)),
            mimeType: dictionary["WebResourceMIMEType"] as? String ?? "application/octet-stream",
            data: data,
            textEncodingName: dictionary["WebResourceTextEncodingName"] as? String
        )
    }

    private static func uniqueFile(for resource: Resource, in directory: URL) -> URL {
        let host = resource.url?.host() ?? "inline"
        var components = (resource.url?.path() ?? "").split(separator: "/").map { safe(String($0)) }
        if components.isEmpty || resource.url?.path().hasSuffix("/") == true {
            components.append("index")
        }
        var name = components.removeLast()
        if (name as NSString).pathExtension.isEmpty,
           let fileExtension = UTType(mimeType: resource.mimeType)?.preferredFilenameExtension {
            name += ".\(fileExtension)"
        }
        let folder = components.reduce(directory.appendingPathComponent(safe(host), isDirectory: true)) {
            $0.appendingPathComponent($1, isDirectory: true)
        }
        var file = folder.appendingPathComponent(name)
        var number = 2
        while FileManager.default.fileExists(atPath: file.path) {
            let base = (name as NSString).deletingPathExtension
            let fileExtension = (name as NSString).pathExtension
            file = folder.appendingPathComponent(fileExtension.isEmpty ? "\(base)-\(number)" : "\(base)-\(number).\(fileExtension)")
            number += 1
        }
        return file
    }

    private static func safe(_ component: String) -> String {
        let cleaned = component.components(separatedBy: CharacterSet(charactersIn: ":\\?*\"<>|")).joined(separator: "-")
        return String((cleaned.isEmpty || cleaned == "." || cleaned == ".." ? "_" : cleaned).prefix(120))
    }
}
