import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum PageImage {
    static func render(size: CGSize, draw: (CGContext) -> Void) throws -> CGImage {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw DriverError.captureFailed }
        context.interpolationQuality = .high
        draw(context)
        guard let image = context.makeImage() else { throw DriverError.captureFailed }
        return image
    }

    static func scaled(_ image: CGImage, to size: CGSize) throws -> CGImage {
        guard image.width != Int(size.width) || image.height != Int(size.height) else { return image }
        return try render(size: size) { $0.draw(image, in: CGRect(origin: .zero, size: size)) }
    }

    static func page(_ pdf: Data, width: CGFloat, maximumHeight: CGFloat) throws -> CGImage {
        guard let provider = CGDataProvider(data: pdf as CFData), let page = CGPDFDocument(provider)?.page(at: 1) else {
            throw DriverError.captureFailed
        }
        let box = page.getBoxRect(.mediaBox)
        guard box.width > 0 else { throw DriverError.captureFailed }
        let pageHeight = box.height * width / box.width
        let size = CGSize(width: width, height: min(pageHeight, maximumHeight))
        return try render(size: size) { context in
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
            context.translateBy(x: 0, y: size.height - pageHeight)
            context.scaleBy(x: width / box.width, y: pageHeight / box.height)
            context.translateBy(x: -box.minX, y: -box.minY)
            context.drawPDFPage(page)
        }
    }

    static func encoded(_ image: CGImage, as type: UTType, quality: Double? = nil) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw DriverError.captureFailed
        }
        let properties = quality.map { [kCGImageDestinationLossyCompressionQuality: $0] as CFDictionary }
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { throw DriverError.captureFailed }
        return data as Data
    }

    static func write(_ image: CGImage, size: CGSize, as type: UTType, quality: Double? = nil, to file: URL) async throws {
        try encoded(try scaled(image, to: size), as: type, quality: quality).write(to: file, options: .atomic)
    }

    static func writePage(_ pdf: Data, width: CGFloat, maximumHeight: CGFloat, to file: URL) async throws {
        try encoded(try page(pdf, width: width, maximumHeight: maximumHeight), as: .png).write(to: file, options: .atomic)
    }
}
