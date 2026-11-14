import Foundation

@MainActor
final class SiteAtlasStore {
    let fileURL: URL
    private(set) lazy var atlas: SiteAtlas = (try? JSONDecoder().decode(SiteAtlas.self, from: Data(contentsOf: fileURL))) ?? SiteAtlas()

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func record(from: PageSignature, label: String, to: PageSignature) {
        let before = atlas
        atlas.record(from: from, label: label, to: to)
        guard atlas != before else { return }
        try? JSONEncoder().encode(atlas).write(to: fileURL, options: .atomic)
    }
}
