import Foundation
import PDFKit

struct PageElement: Equatable {
    let text: String
    let frame: CGRect
    let link: URL?

    var center: CGPoint {
        CGPoint(x: frame.midX.rounded(), y: frame.midY.rounded())
    }

    var description: String {
        let position = "\(Int(center.x)),\(Int(center.y))".padding(toLength: 10, withPad: " ", startingAt: 0)
        let quoted = "“\(text)”"
        return link.map { "\(position)link \(quoted) → \($0.absoluteString)" } ?? "\(position)\(quoted)"
    }
}

enum PageMap {
    static func elements(fromPDF data: Data, viewWidth: CGFloat) -> [PageElement] {
        guard let document = PDFDocument(data: data), let page = document.page(at: 0) else { return [] }
        let box = page.bounds(for: .mediaBox)
        let scale = box.width > 0 ? viewWidth / box.width : 1

        func viewRect(_ rect: CGRect) -> CGRect {
            CGRect(
                x: (rect.minX - box.minX) * scale,
                y: (box.maxY - rect.maxY) * scale,
                width: rect.width * scale,
                height: rect.height * scale
            )
        }

        let links = page.annotations.compactMap { annotation in
            annotation.url.map { (url: $0, frame: viewRect(annotation.bounds)) }
        }
        return chunks(of: page).compactMap { chunk in
            let frame = viewRect(chunk.rect)
            let link = links.first { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) }?.url
            guard link != nil || chunk.text.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
            return PageElement(text: chunk.text, frame: frame, link: link)
        }
        .sorted { ($0.frame.minY.rounded(), $0.frame.minX) < ($1.frame.minY.rounded(), $1.frame.minX) }
    }

    struct Hit: Equatable {
        let frame: CGRect
        let whole: Bool
    }

    static func hits(of query: String, inPDF data: Data, viewWidth: CGFloat) -> [Hit] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty, let document = PDFDocument(data: data) else { return [] }
        let pages = (0..<document.pageCount).compactMap { document.page(at: $0)?.bounds(for: .mediaBox) }
        let tops = pages.reduce(into: [CGFloat.zero]) { $0.append(($0.last ?? 0) + $1.height) }
        return document.findString(needle, withOptions: [.caseInsensitive, .diacriticInsensitive]).compactMap { selection in
            guard let page = selection.pages.first else { return nil }
            let index = document.index(for: page)
            guard pages.indices.contains(index) else { return nil }
            let box = pages[index]
            let bounds = selection.bounds(for: page)
            let scale = box.width > 0 ? viewWidth / box.width : 1
            let frame = CGRect(
                x: (bounds.minX - box.minX) * scale,
                y: (tops[index] + box.maxY - bounds.maxY) * scale,
                width: bounds.width * scale,
                height: bounds.height * scale
            )
            return Hit(frame: frame, whole: isWhole(selection))
        }
    }

    static func closest(_ hits: [Hit], to visible: CGRect) -> Hit? {
        hits.min { lhs, rhs in
            (lhs.whole ? 0 : 1, distance(lhs.frame, visible)) < (rhs.whole ? 0 : 1, distance(rhs.frame, visible))
        }
    }

    private static func distance(_ frame: CGRect, _ visible: CGRect) -> CGFloat {
        max(visible.minY - frame.midY, frame.midY - visible.maxY, 0) + max(visible.minX - frame.midX, frame.midX - visible.maxX, 0)
    }

    private static func isWhole(_ selection: PDFSelection) -> Bool {
        guard let widened = selection.copy() as? PDFSelection else { return false }
        widened.extend(atStart: 1)
        widened.extend(atEnd: 1)
        let text = Array(widened.string ?? "")
        let found = Array(selection.string ?? "")
        guard let start = text.indices.first(where: { Array(text[$0...].prefix(found.count)) == found }) else { return false }
        let before = start > 0 ? text[start - 1] : nil
        let after = start + found.count < text.count ? text[start + found.count] : nil
        return [before, after].allSatisfy { !($0?.isLetter ?? false) && !($0?.isNumber ?? false) }
    }

    static func match(_ query: String, in elements: [PageElement], wholeWords: Bool = false) -> [PageElement] {
        match(query, in: elements, by: \.text, wholeWords: wholeWords)
    }

    static func match<Item>(_ query: String, in items: [Item], by text: (Item) -> String, wholeWords: Bool = false) -> [Item] {
        let needle = query.matchKey
        guard !needle.isEmpty else { return [] }
        let keyed = items.map { (item: $0, key: text($0).matchKey) }
        let exact = keyed.filter { $0.key == needle }
        if !exact.isEmpty { return exact.map(\.item) }
        let partial = wholeWords ? keyed.filter { TextMatch.find(needle, in: $0.key, wholeWords: true) != nil } : keyed
        let prefix = partial.filter { $0.key.hasPrefix(needle) }
        if !prefix.isEmpty { return prefix.map(\.item) }
        return partial.filter { $0.key.contains(needle) }.map(\.item)
    }

    private static func chunks(of page: PDFPage) -> [(text: String, rect: CGRect)] {
        var chunks: [(text: String, rect: CGRect)] = []
        var text = ""
        var rect = CGRect.null
        var last = CGRect.null

        func flush() {
            let trimmed = text.withoutPrivateUse.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                chunks.append((trimmed, rect))
            }
            text = ""
            rect = .null
        }

        for index in 0..<page.numberOfCharacters {
            guard let selection = page.selection(for: NSRange(location: index, length: 1)),
                  let character = selection.string, !character.isEmpty else { continue }
            if character.contains(where: \.isNewline) {
                flush()
                continue
            }
            if character.allSatisfy(\.isWhitespace) {
                if !text.isEmpty, !text.hasSuffix(" ") { text += " " }
                continue
            }
            let bounds = selection.bounds(for: page)
            let overlap = bounds.intersection(last)
            if bounds.isEmpty || bounds.width <= 0 || (!overlap.isNull && overlap.width > bounds.width * 0.5) {
                continue
            }
            last = bounds
            if !rect.isNull {
                let lineHeight = max(rect.height, bounds.height)
                let sameLine = abs(bounds.midY - rect.midY) < lineHeight * 0.6
                let gap = bounds.minX - rect.maxX
                if !sameLine || gap > lineHeight * 1.2 || gap < -lineHeight {
                    flush()
                }
            }
            text += character
            rect = rect.isNull ? bounds : rect.union(bounds)
        }
        flush()
        return chunks
    }
}
