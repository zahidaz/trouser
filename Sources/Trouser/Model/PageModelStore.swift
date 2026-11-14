import Foundation

@MainActor
final class PageModelStore {
    private(set) var generation = 0
    private(set) var focus: String?
    private let driver: PageDriver
    private let dialogs: DialogGate
    private let precise: PreciseLink?
    private let unlinked: PreciseStatus
    private let lastActivity: () -> ContinuousClock.Instant?
    private let registry = ElementRegistry()
    private var cached: (model: PageModel, started: ContinuousClock.Instant, revision: Int?, origin: CGPoint?)?
    private var rendering: (generation: Int, task: Task<PageModel, Error>)?
    private var shown: PageModel?
    private(set) var latest: PageModel?

    private static let lifetime: Duration = .seconds(3)
    private static let focusPoll: Duration = .milliseconds(5)

    init(
        driver: PageDriver,
        dialogs: DialogGate = DialogGate(),
        precise: PreciseLink? = nil,
        unlinked: PreciseStatus = .off,
        lastActivity: @escaping () -> ContinuousClock.Instant?
    ) {
        self.driver = driver
        self.dialogs = dialogs
        self.precise = precise
        self.unlinked = unlinked
        self.lastActivity = lastActivity
    }

    var isCurrent: Bool {
        guard let cached, driver.viewportOrigin == cached.origin else { return false }
        if let revision = cached.revision, let live = precise?.live {
            return live.revision == revision
        }
        return lastActivity().map { $0 < cached.started } ?? true
    }

    var isRendering: Bool {
        rendering != nil
    }

    var fresh: PageModel? {
        guard let cached, pushed == nil, driver.viewportOrigin == cached.origin else { return nil }
        return isCurrent || ContinuousClock.now - cached.started < Self.lifetime ? cached.model : nil
    }

    var confirmed: PageModel? {
        isCurrent ? cached?.model : nil
    }

    var baseline: PageModel? {
        shown ?? latest
    }

    func invalidate(focus: String? = nil) {
        generation += 1
        self.focus = focus
        cached = nil
    }

    func refresh(recognizing: Bool = false) async throws -> PageModel {
        if !recognizing, let rendering, rendering.generation == generation {
            return try await dialogs.value(of: rendering.task)
        }
        try dialogs.check()
        let generation = generation
        let task = Task { try await render(generation: generation, recognizing: recognizing) }
        if !recognizing {
            rendering = (generation, task)
        }
        defer {
            if rendering?.generation == generation {
                rendering = nil
            }
        }
        return try await dialogs.value(of: task)
    }

    func snapshot() async throws -> PageModel {
        if let pushed {
            return try await rebuild(from: pushed)
        }
        if isCurrent, let cached {
            return cached.model
        }
        return try await refresh()
    }

    func current() async throws -> PageModel {
        if let pushed {
            return try await rebuild(from: pushed)
        }
        if let fresh {
            return fresh
        }
        return try await refresh()
    }

    func search<Found>(_ find: (PageModel) throws -> Found) async throws -> Found {
        do {
            return try find(try await current())
        } catch let error as ModelError where error.isMiss {
            return try find(try await refresh())
        }
    }

    func pressPoint(for element: ModelElement) async -> CGPoint? {
        guard let precise, precise.status == .active else { return element.center }
        return await Self.pressPoint(for: element) { await precise.hit(at: $0) }
    }

    static func pressPoint(for element: ModelElement, hitTest: (CGPoint) async -> PreciseHitReply?) async -> CGPoint? {
        guard let frame = element.frame, let center = element.center else { return element.center }
        let inset = CGPoint(x: frame.minX + min(8, frame.width / 2), y: frame.minY + min(8, frame.height / 2))
        for point in [center, CGPoint(x: inset.x, y: center.y), inset] {
            guard let reply = await hitTest(point) else { break }
            if reply.hit?.label.matchKey == element.label.matchKey {
                return point
            }
        }
        return center
    }

    func focusMoved(since start: ContinuousClock.Instant, within limit: Duration) async throws {
        guard let precise, precise.status == .active else {
            try await Task.sleep(for: limit)
            return
        }
        _ = try await Reaction.read({ precise.lastFocus }, within: limit, every: Self.focusPoll) { $0.map { $0 >= start } ?? false }
    }

    func reveal(_ text: String) async throws -> PageElement {
        try dialogs.check()
        return try await driver.reveal(text) { [self] in
            guard let snapshot = await precise?.snapshot() else { return try await driver.elements() }
            return PreciseMapping.texts(PreciseMapping.elements(snapshot, viewport: driver.webView.bounds.size))
        }
    }

    func visibleTexts() async throws -> [PageElement] {
        try dialogs.check()
        guard precise?.status == .active else { return try await driver.elements() }
        return PreciseMapping.texts(try await current().elements)
    }

    private var pushed: PreciseSnapshot? {
        guard let cached, let revision = cached.revision, let live = precise?.live, live.revision != revision, !live.nodes.isEmpty else {
            return nil
        }
        return live
    }

    private func rebuild(from live: PreciseSnapshot) async throws -> PageModel {
        let started = ContinuousClock.now
        let origin = driver.viewportOrigin
        return store(try await driver.capture(live, generation: generation, recognizing: false), generation: generation, started: started, origin: origin)
    }

    private func render(generation: Int, recognizing: Bool) async throws -> PageModel {
        let started = ContinuousClock.now
        let origin = driver.viewportOrigin
        return store(try await capture(generation: generation, recognizing: recognizing), generation: generation, started: started, origin: origin)
    }

    private func capture(generation: Int, recognizing: Bool) async throws -> PageCapture {
        guard let precise else { return try await driver.capture(generation: generation, precise: unlinked, recognizing: recognizing) }
        if let snapshot = await precise.snapshot() {
            return try await driver.capture(snapshot, generation: generation, recognizing: recognizing)
        }
        let status = precise.status == .active ? .unavailable("the page did not answer") : precise.status
        return try await driver.capture(generation: generation, precise: status, recognizing: recognizing)
    }

    private func store(_ capture: PageCapture, generation: Int, started: ContinuousClock.Instant, origin: CGPoint?) -> PageModel {
        let identified = registry.assign(capture.elements)
        let elements = capture.revision == nil ? carryingValues(into: identified, at: capture.info.url) : identified
        let focused = capture.focused.flatMap { identity in identified.first { $0.identity == identity }?.id }
        let model = PageModel(page: capture.info, focus: focused ?? focus, elements: ModelFusion.readingOrder(elements))
        latest = model
        if generation == self.generation {
            cached = (model, started, capture.revision, origin)
        }
        return model
    }

    private func carryingValues(into elements: [ModelElement], at url: URL?) -> [ModelElement] {
        guard let latest, latest.page.document == PageInfo.document(of: url) else { return elements }
        let seen = Dictionary(latest.elements.map { ($0.id, $0.value) }, uniquingKeysWith: { first, _ in first })
        return elements.map { element in
            guard !element.visible, element.role.showsValue, let value = seen[element.id] else { return element }
            var carried = element
            carried.value = value
            return carried
        }
    }

    func record(_ model: PageModel) {
        shown = model
    }
}
