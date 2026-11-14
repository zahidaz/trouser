import AppKit
import WebKit

struct PageCapture {
    let info: PageInfo
    let elements: [ModelElement]
    var revision: Int?
    var focused: String?
}

extension PageDriver {
    func capture(generation: Int, precise: PreciseStatus, recognizing: Bool) async throws -> PageCapture {
        let base = webView.url
        async let rendered = placedElements()
        async let parsed = Self.controls(inHTML: try await archive().main.text, base: base)
        async let recognized: [PageElement] = recognizing ? try await recognizedText() : []
        let (placed, controls, extra) = try await (rendered, parsed, recognized)
        let texts = placed ?? []
        return PageCapture(
            info: info(generation: generation, precise: precise, placed: placed != nil),
            elements: ModelFusion.elements(controls: controls, texts: texts, recognized: extra)
        )
    }

    private func placedElements() async throws -> [PageElement]? {
        do {
            return try await elements()
        } catch DriverError.unplaced {
            return nil
        }
    }

    private nonisolated static func controls(inHTML html: String, base: URL?) async throws -> [DOMControl] {
        try PageControls.controls(inHTML: html, base: base)
    }

    func capture(_ snapshot: PreciseSnapshot, generation: Int, recognizing: Bool) async throws -> PageCapture {
        let elements = PreciseMapping.elements(snapshot, viewport: webView.bounds.size)
        let recognized = recognizing ? ModelFusion.unrecognized(try await recognizedText(), known: elements.filter(\.visible).compactMap(\.frame)) : []
        return PageCapture(
            info: info(generation: generation, precise: .active),
            elements: elements + recognized,
            revision: snapshot.revision,
            focused: snapshot.nodes.first { $0.focused == true }?.identity
        )
    }

    private func info(generation: Int, precise: PreciseStatus, placed: Bool = true) -> PageInfo {
        PageInfo(
            url: webView.url,
            title: webView.title ?? "",
            loading: webView.isLoading,
            progress: webView.estimatedProgress,
            secure: webView.url?.scheme == "https" && webView.serverTrust != nil,
            onlySecureContent: webView.hasOnlySecureContent,
            generation: generation,
            viewport: webView.bounds.size,
            precise: precise,
            placed: placed
        )
    }

    private func recognizedText() async throws -> [PageElement] {
        let size = webView.bounds.size
        return try await TextRecognizer.lines(in: try await snapshot(), viewSize: size)
    }
}
