import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Trouser

struct PageImageTests {
    private func filled(_ size: CGSize, top: CGColor, bottom: CGColor) throws -> CGImage {
        try PageImage.render(size: size) { context in
            context.setFillColor(bottom)
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height / 2))
            context.setFillColor(top)
            context.fill(CGRect(x: 0, y: size.height / 2, width: size.width, height: size.height / 2))
        }
    }

    private func pdf(width: CGFloat, height: CGFloat, origin: CGPoint) -> Data {
        let data = NSMutableData()
        var box = CGRect(origin: origin, size: CGSize(width: width, height: height))
        let consumer = CGDataConsumer(data: data)!
        let context = CGContext(consumer: consumer, mediaBox: &box, nil)!
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: origin.x, y: origin.y, width: width, height: height / 2))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: origin.x, y: origin.y + height / 2, width: width, height: height / 2))
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> (red: UInt8, green: UInt8, blue: UInt8) {
        let bitmap = NSBitmapImageRep(cgImage: image)
        let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
        return (UInt8(color.redComponent * 255), UInt8(color.greenComponent * 255), UInt8(color.blueComponent * 255))
    }

    private func decoded(_ data: Data) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    @Test func scalesToOnePixelPerPoint() throws {
        let retina = try filled(CGSize(width: 200, height: 100), top: CGColor(red: 1, green: 0, blue: 0, alpha: 1), bottom: CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        let scaled = try PageImage.scaled(retina, to: CGSize(width: 100, height: 50))
        #expect(scaled.width == 100)
        #expect(scaled.height == 50)
        #expect(try pixel(scaled, x: 50, y: 5).red > 200)
        #expect(try pixel(scaled, x: 50, y: 45).blue > 200)
    }

    @Test func keepsAnImageThatIsAlreadyTheRightSize() throws {
        let image = try filled(CGSize(width: 10, height: 10), top: CGColor(gray: 0, alpha: 1), bottom: CGColor(gray: 1, alpha: 1))
        #expect(try PageImage.scaled(image, to: CGSize(width: 10, height: 10)) === image)
    }

    @Test func encodesJPEGAndPNG() throws {
        let image = try filled(CGSize(width: 40, height: 30), top: CGColor(red: 1, green: 0, blue: 0, alpha: 1), bottom: CGColor(gray: 1, alpha: 1))
        for (type, magic) in [(UTType.jpeg, [UInt8]([0xFF, 0xD8])), (.png, [0x89, 0x50])] {
            let data = try PageImage.encoded(image, as: type, quality: type == .jpeg ? 0.4 : nil)
            #expect(Array(data.prefix(2)) == magic)
            let decoded = try decoded(data)
            #expect(decoded.width == 40 && decoded.height == 30)
        }
    }

    @Test func lowerQualityMakesSmallerJPEGs() throws {
        let image = try PageImage.render(size: CGSize(width: 200, height: 200)) { context in
            for index in 0..<200 {
                context.setFillColor(CGColor(red: CGFloat(index % 7) / 7, green: CGFloat(index % 11) / 11, blue: CGFloat(index % 13) / 13, alpha: 1))
                context.fill(CGRect(x: index, y: (index * 37) % 200, width: 3, height: 50))
            }
        }
        #expect(try PageImage.encoded(image, as: .jpeg, quality: 0.4).count < PageImage.encoded(image, as: .jpeg, quality: 0.95).count)
    }

    @Test func drawsThePDFTopAtTheTopOfTheImage() throws {
        for origin in [CGPoint.zero, CGPoint(x: 0, y: 300)] {
            let image = try PageImage.page(pdf(width: 200, height: 400, origin: origin), width: 100, maximumHeight: 1_000)
            #expect(image.width == 100 && image.height == 200)
            #expect(try pixel(image, x: 50, y: 10).red > 200)
            #expect(try pixel(image, x: 50, y: 190).blue > 200)
        }
    }

    @Test func cutsTallPagesAtTheMaximumHeightKeepingTheTop() throws {
        let image = try PageImage.page(pdf(width: 100, height: 1_000, origin: .zero), width: 100, maximumHeight: 300)
        #expect(image.height == 300)
        #expect(try pixel(image, x: 50, y: 290).red > 200)
    }

    @Test func liveFramesArePrivateJPEGs() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).live.jpg")
        defer { try? FileManager.default.removeItem(at: file) }
        let image = try filled(CGSize(width: 80, height: 60), top: CGColor(gray: 0, alpha: 1), bottom: CGColor(gray: 1, alpha: 1))
        try await LiveScreenshot.write(image, size: CGSize(width: 40, height: 30), to: file)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let decoded = try decoded(Data(contentsOf: file))
        #expect(decoded.width == 40 && decoded.height == 30)
    }
}
