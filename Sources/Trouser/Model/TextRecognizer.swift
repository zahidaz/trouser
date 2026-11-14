import CoreGraphics
import Vision

enum TextRecognizer {
    static func lines(in image: CGImage, viewSize: CGSize) async throws -> [PageElement] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: image).perform([request])
            return (request.results ?? []).compactMap { observation in
                guard let text = observation.topCandidates(1).first?.string, text.contains(where: { $0.isLetter || $0.isNumber }) else {
                    return nil
                }
                let box = observation.boundingBox
                let frame = CGRect(
                    x: box.minX * viewSize.width,
                    y: (1 - box.maxY) * viewSize.height,
                    width: box.width * viewSize.width,
                    height: box.height * viewSize.height
                )
                return PageElement(text: text, frame: frame, link: nil)
            }
        }.value
    }
}
