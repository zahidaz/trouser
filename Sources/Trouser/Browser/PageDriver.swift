import AppKit
import WebKit

enum DriverError: LocalizedError {
    case outsidePage(CGPoint, CGSize)
    case windowUnavailable
    case eventUnavailable
    case captureFailed
    case notFound(String)
    case unanswered(Duration)
    case unplaced

    var errorDescription: String? {
        switch self {
        case .outsidePage(let point, let size):
            "point (\(Int(point.x)), \(Int(point.y))) is outside the page (\(Int(size.width))×\(Int(size.height)))"
        case .windowUnavailable: "the tab has no window"
        case .eventUnavailable: "could not create the input event"
        case .captureFailed: "could not capture the page"
        case .notFound(let text): "no element matches “\(text)” anywhere on the page"
        case .unanswered(let limit): "the page did not answer within \(limit.components.seconds) s"
        case .unplaced: "could not tell where the page is scrolled to, so positions on it are unknown; use coordinates from: trouser screenshot"
        }
    }
}

@MainActor
struct PageDriver {
    let webView: WKWebView

    var pageDescription: String {
        let title = webView.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled"
        return "\(title) — \(webView.url?.absoluteString ?? "about:blank")"
    }

    func perform(_ action: PageAction) throws {
        switch action {
        case .brief, .state, .query, .act, .intent, .find, .screenshot, .source, .tab, .drag: break
        case .click(let point, let count):
            try click(at: point, count: count)
        case .scroll(let point, let dx, let dy): try scroll(at: point, dx: dx, dy: dy)
        case .type(let text): try type(text)
        case .key(let combo): try press(combo.keyCode, combo.characters, combo.modifiers)
        case .navigate(let navigation): navigate(navigation)
        }
    }

    func focus() {
        webView.window?.makeFirstResponder(webView)
    }

    var viewportOrigin: CGPoint? {
        webView.layer.flatMap(ViewportOrigin.read)
    }

    func elements() async throws -> [PageElement] {
        let bounds = webView.bounds
        for _ in 0..<Self.originAttempts {
            guard let origin = viewportOrigin else { break }
            let configuration = WKPDFConfiguration()
            configuration.rect = bounds.offsetBy(dx: origin.x, dy: origin.y)
            let data = try await pdf(configuration)
            if viewportOrigin == origin {
                return await Self.texts(inPDF: data, bounds: bounds)
            }
        }
        throw DriverError.unplaced
    }

    func snapshot(onePixelPerPoint: Bool = false) async throws -> CGImage {
        let configuration = WKSnapshotConfiguration()
        let scale = onePixelPerPoint ? webView.window?.backingScaleFactor ?? 1 : 1
        configuration.snapshotWidth = NSNumber(value: Double(webView.bounds.width / scale))
        return try await WebKitReply.value(within: Self.answerLimit) { reply in
            webView.takeSnapshot(with: configuration) { image, error in
                let cgImage = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
                reply(cgImage.map { .success($0) } ?? .failure(error ?? DriverError.captureFailed))
            }
        }
    }

    private func pdf(_ configuration: WKPDFConfiguration) async throws -> Data {
        try await WebKitReply.value(within: Self.answerLimit) { reply in
            webView.createPDF(configuration: configuration) { reply($0) }
        }
    }

    private nonisolated static func texts(inPDF data: Data, bounds: CGRect) async -> [PageElement] {
        PageMap.elements(fromPDF: data, viewWidth: bounds.width).filter { bounds.contains($0.center) }
    }

    func reveal(_ text: String, reading texts: () async throws -> [PageElement]) async throws -> PageElement {
        let center = CGPoint(x: webView.bounds.midX, y: webView.bounds.midY)
        let step = webView.bounds.height * 0.8
        var elements = try await texts()
        var wholeWords = true
        if PageMap.match(text, in: elements, wholeWords: true).isEmpty, let origin = viewportOrigin {
            let visible = CGRect(origin: origin, size: webView.bounds.size)
            let hits = await Self.hits(of: text, inPDF: try await pdf(WKPDFConfiguration()), width: visible.width)
            wholeWords = hits.isEmpty || hits.contains(where: \.whole)
            if let hit = PageMap.closest(hits, to: visible)?.frame {
                let dx = hit.midX < visible.minX || hit.midX > visible.maxX ? hit.midX - visible.midX : 0
                elements = try await scrolled(at: center, dx: dx, dy: hit.midY - visible.minY - visible.height * 0.4, from: elements, reading: texts)
            }
        }
        let anchors = Self.anchors(in: webView.bounds)
        for direction in [1.0, -1.0] {
            var anchor = anchors.startIndex
            var steps = 0
            while steps < Self.revealSteps, anchor < anchors.endIndex {
                if let match = PageMap.match(text, in: elements, wholeWords: wholeWords).first {
                    return try await centered(match, text: text, wholeWords: wholeWords, in: elements, reading: texts)
                }
                let moved = try await scrolled(at: anchors[anchor], dy: direction * step, from: elements, reading: texts)
                if moved == elements {
                    anchor += 1
                } else {
                    elements = moved
                    steps += 1
                }
            }
        }
        throw DriverError.notFound(text)
    }

    static func anchors(in bounds: CGRect) -> [CGPoint] {
        let fractions = [0.5, 0.25, 0.75]
        return fractions.flatMap { y in fractions.map { x in CGPoint(x: bounds.minX + bounds.width * x, y: bounds.minY + bounds.height * y) } }
    }

    private nonisolated static func hits(of text: String, inPDF data: Data, width: CGFloat) async -> [PageMap.Hit] {
        PageMap.hits(of: text, inPDF: data, viewWidth: width)
    }

    private func centered(
        _ element: PageElement,
        text: String,
        wholeWords: Bool,
        in elements: [PageElement],
        reading texts: () async throws -> [PageElement]
    ) async throws -> PageElement {
        let offset = element.center.y - webView.bounds.height * 0.4
        guard abs(offset) > webView.bounds.height * 0.15 else { return element }
        let moved = try await scrolled(at: element.center, dy: offset, from: elements, reading: texts)
        return PageMap.match(text, in: moved, wholeWords: wholeWords).first ?? element
    }

    private func scrolled(
        at center: CGPoint,
        dx: Double = 0,
        dy: Double,
        from elements: [PageElement],
        reading texts: () async throws -> [PageElement]
    ) async throws -> [PageElement] {
        let positions = scrollPositions
        try scroll(at: center, dx: dx, dy: dy)
        if !positions.isEmpty, try await Reaction.read({ scrollPositions }, within: Reaction.scrollAnswer, every: Reaction.scrollPoll, until: { $0 != positions }) == positions {
            return elements
        }
        return try await Reaction.read(texts, within: Reaction.scrollLimit) { $0 != elements }
    }

    private var scrollPositions: [CGPoint] {
        webView.layer.map(ViewportOrigin.scrollPositions) ?? []
    }

    func screenshot(to file: URL, fullPage: Bool) async throws {
        if fullPage {
            try await PageImage.writePage(try await pdf(WKPDFConfiguration()), width: webView.bounds.width, maximumHeight: Self.maximumPageHeight, to: file)
        } else {
            try await PageImage.write(try await snapshot(onePixelPerPoint: true), size: webView.bounds.size, as: .png, to: file)
        }
    }

    private static let maximumPageHeight: CGFloat = 30_000
    private static let revealSteps = 30
    private static let originAttempts = 3
    private static let answerLimit: Duration = .seconds(10)
    private static let pressDuration: TimeInterval = 0.05
    private static let dragSteps = 12
    private static let dragInterval: Duration = .milliseconds(16)

    func archive() async throws -> WebArchive {
        let data: Data = try await WebKitReply.value(within: Self.answerLimit) { reply in
            webView.createWebArchiveData { reply($0) }
        }
        return try WebArchive(data: data)
    }

    private func click(at point: CGPoint, count: Int) throws {
        let location = try windowLocation(of: point)
        var timestamp = ProcessInfo.processInfo.systemUptime
        for click in 1...count {
            try sendMouse(.leftMouseDown, at: location, clickCount: click, timestamp: timestamp)
            timestamp += Self.pressDuration
            try sendMouse(.leftMouseUp, at: location, clickCount: click, timestamp: timestamp)
        }
    }

    func drag(from start: CGPoint, to end: CGPoint) async throws {
        let origin = try windowLocation(of: start)
        let target = try windowLocation(of: end)
        try sendMouse(.leftMouseDown, at: origin, clickCount: 1, timestamp: ProcessInfo.processInfo.systemUptime)
        for step in 1...Self.dragSteps {
            try await Task.sleep(for: Self.dragInterval)
            let progress = CGFloat(step) / CGFloat(Self.dragSteps)
            let location = NSPoint(x: origin.x + (target.x - origin.x) * progress, y: origin.y + (target.y - origin.y) * progress)
            try sendMouse(.leftMouseDragged, at: location, clickCount: 1, timestamp: ProcessInfo.processInfo.systemUptime)
        }
        try await Task.sleep(for: Self.dragInterval)
        try sendMouse(.leftMouseUp, at: target, clickCount: 1, timestamp: ProcessInfo.processInfo.systemUptime)
    }

    private func scroll(at point: CGPoint, dx: Double, dy: Double) throws {
        let location = try windowLocation(of: point)
        guard let window = webView.window, let screen = NSScreen.screens.first, let cgEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(-dy),
            wheel2: Int32(-dx),
            wheel3: 0
        ) else { throw DriverError.eventUnavailable }
        let onScreen = window.convertPoint(toScreen: location)
        cgEvent.location = CGPoint(x: onScreen.x, y: screen.frame.maxY - onScreen.y)
        guard let event = NSEvent(cgEvent: cgEvent) else { throw DriverError.eventUnavailable }
        webView.scrollWheel(with: event)
    }

    private func type(_ text: String) throws {
        for character in text {
            if character == "\n" {
                try press(KeyMap.enter.code, KeyMap.enter.characters, [])
            } else {
                try press(KeyMap.code(for: character), String(character), character.isUppercase ? .shift : [])
            }
        }
    }

    private func press(_ code: UInt16, _ characters: String, _ modifiers: NSEvent.ModifierFlags) throws {
        guard let window = webView.window else { throw DriverError.windowUnavailable }
        if let command = KeyMap.editingCommand(characters: characters, modifiers: modifiers),
           webView.tryToPerform(command, with: nil) {
            return
        }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(
                with: type,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: code
            ) else { throw DriverError.eventUnavailable }
            if type == .keyDown {
                webView.keyDown(with: event)
            } else {
                webView.keyUp(with: event)
            }
        }
    }

    private func navigate(_ navigation: Navigation) {
        switch navigation {
        case .url(let url): webView.load(URLRequest(url: url))
        case .back: webView.goBack()
        case .forward: webView.goForward()
        case .reload: webView.reload()
        }
    }

    private func sendMouse(_ type: NSEvent.EventType, at location: NSPoint, clickCount: Int, timestamp: TimeInterval) throws {
        guard let window = webView.window else { throw DriverError.windowUnavailable }
        guard let event = NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: timestamp,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: clickCount,
            pressure: type == .leftMouseUp ? 0 : 1
        ) else { throw DriverError.eventUnavailable }
        switch type {
        case .leftMouseDown: webView.mouseDown(with: event)
        case .leftMouseDragged: webView.mouseDragged(with: event)
        default: webView.mouseUp(with: event)
        }
    }

    func validate(_ point: CGPoint) throws {
        let bounds = webView.bounds
        guard point.x >= 0, point.y >= 0, point.x < bounds.width, point.y < bounds.height else {
            throw DriverError.outsidePage(point, bounds.size)
        }
    }

    private func windowLocation(of point: CGPoint) throws -> NSPoint {
        try validate(point)
        let bounds = webView.bounds
        let local = NSPoint(x: point.x, y: webView.isFlipped ? point.y : bounds.height - point.y)
        return webView.convert(local, to: nil)
    }
}
