import Foundation

struct PageBrief: Equatable {
    struct Item: Equatable, Encodable {
        var id: String?
        var role: ElementRole?
        var label: String
        var value: String?
        var states: [ElementState] = []
        var note: String?
        var destination: String?
        var similar = 0

        init(note: String, label: String) {
            self.label = label
            self.note = note
        }

        init(_ element: ModelElement, note: String? = nil, destination: String? = nil) {
            id = element.id
            role = element.role
            label = element.name
            value = element.value
            states = element.states
            self.note = note
            self.destination = destination
        }

        var line: String {
            guard let id, let role else { return "\(note ?? ""): “\(label)”" }
            var line = "\(id) \(role.rawValue) “\(label)”"
            if let value {
                line += " = “\(value)”"
            } else if role.showsValue {
                line += " (empty)"
            }
            if !states.isEmpty {
                line += " " + states.map(\.rawValue).joined(separator: " ")
            }
            if similar > 0 {
                line += " (+\(similar) similar)"
            }
            if let note {
                line += " — \(note)"
            }
            if let destination {
                line += " → \(destination)"
            }
            return line
        }
    }

    struct Signals {
        var approval: String?
        var destinations: [String: String] = [:]
    }

    let title: String
    let url: URL?
    let loading: Bool
    private(set) var headings: [Item] = []
    private(set) var blockers: [Item] = []
    private(set) var actions: [Item] = []
    private(set) var fields: [Item] = []
    private(set) var navigation: [Item] = []
    private(set) var omitted = 0

    static let headingLimit = 2
    static let blockerLimit = 6
    static let actionLimit = 8
    static let fieldLimit = 6
    static let navigationLimit = 8
    static let noticeLimit = 3
    static let explanationReach: CGFloat = 80

    init(model: PageModel, signals: Signals = Signals()) {
        title = model.page.title
        url = model.page.url
        loading = model.page.loading
        let destinations = signals.destinations
        func item(_ element: ModelElement, note: String? = nil) -> Item {
            Item(element, note: note, destination: destinations[element.name.matchKey])
        }

        headings = model.elements.filter { $0.role == .heading && $0.visible }.prefix(Self.headingLimit).map { item($0) }
        blockers = Array(Self.blockers(in: model, signals: signals, item: item).prefix(Self.blockerLimit))
        let blocking = Set(blockers.compactMap(\.id))
        let controls = model.elements.filter { $0.source == .dom && !blocking.contains($0.id) }

        let fieldElements = controls.filter(\.role.isField)
        fields = Array(Self.prominent(fieldElements).prefix(Self.fieldLimit)).map { item($0) }

        let actionable = controls.filter { $0.role.isActionable && !$0.role.isField && !$0.states.contains(.disabled) }
        let primary = actionable.filter { Self.isPrimary($0) }
        actions = Array(Self.grouped(Self.ranked(primary), item: item).prefix(Self.actionLimit))

        let shown = Set(actions.compactMap(\.id))
        let links = actionable.filter { ($0.role == .link || $0.role == .tab) && $0.visible && !shown.contains($0.id) }
        navigation = Array(Self.grouped(links, item: item).prefix(Self.navigationLimit))

        let listed = headings.count + blockers.count + fields.count + actions.count + navigation.count
        omitted = max(0, controls.filter(\.role.isActionable).count - listed)
    }

    var lines: [String] {
        var lines = [header]
        lines += headings.map { "# \($0.id ?? "") “\($0.label)”" }
        lines += blockers.map { "! \($0.line)" }
        lines += actions.map { "> \($0.line)" }
        lines += fields.map { "= \($0.line)" }
        if !navigation.isEmpty {
            lines.append("nav: " + navigation.map { "\($0.id ?? "") “\($0.label)”" + ($0.destination.map { " → \($0)" } ?? "") }.joined(separator: " · "))
        }
        if omitted > 0 {
            lines.append("\(omitted) more controls; run: trouser page --all")
        }
        return lines
    }

    var header: String {
        let path = url.map { [$0.path(), $0.query().map { "?\($0)" }].compactMap { $0 }.joined() } ?? "about:blank"
        return "\(title.isEmpty ? "Untitled" : title) — \(url?.host() ?? "")\(path)\(loading ? " (loading)" : "")"
    }

    func delta(from before: PageBrief) -> [String] {
        let old = before.lines
        let new = lines
        return old.filter { !new.contains($0) }.map { "- \($0)" } + new.filter { !old.contains($0) }.map { "+ \($0)" }
    }

    func json() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(Payload(brief: self)), as: UTF8.self)
    }

    private struct Payload: Encodable {
        let title: String
        let url: String?
        let loading: Bool
        let headings: [Item]
        let blockers: [Item]
        let actions: [Item]
        let fields: [Item]
        let navigation: [Item]
        let omitted: Int

        init(brief: PageBrief) {
            title = brief.title
            url = brief.url?.absoluteString
            loading = brief.loading
            headings = brief.headings
            blockers = brief.blockers
            actions = brief.actions
            fields = brief.fields
            navigation = brief.navigation
            omitted = brief.omitted
        }
    }

    private static func blockers(in model: PageModel, signals: Signals, item: (ModelElement, String?) -> Item) -> [Item] {
        var blockers: [Item] = []
        if let approval = signals.approval {
            blockers.append(Item(note: "waiting for approval", label: approval))
        }
        let texts = model.elements.filter { $0.visible && $0.source != .dom }
        let shownTexts = Set(texts.map(\.label.matchKey))
        for element in model.elements where element.role.isContainer && shownTexts.contains(element.label.matchKey) {
            blockers.append(item(element, nil))
        }
        for element in model.elements where element.source == .dom && element.role.isField {
            if element.states.contains(.invalid) {
                blockers.append(item(element, nil))
            } else if element.states.contains(.required), element.value == nil, element.role.isFillable {
                blockers.append(item(element, nil))
            }
        }
        var explained: Set<String> = []
        for element in model.elements where element.source == .dom && element.visible && element.states.contains(.disabled) && isPrimary(element) {
            let reason = explanation(for: element, among: texts)
            if let reason {
                explained.insert(reason.matchKey)
            }
            blockers.append(item(element, reason.map { "“\($0.count > 80 ? $0.prefix(80) + "…" : $0)”" }))
        }
        let covered = blockers.map(\.label.matchKey) + explained
        let notices = texts.filter { text in
            isNotice(text.label) && !covered.contains { $0.contains(text.label.matchKey) || text.label.matchKey.contains($0) }
        }
        return blockers + notices.prefix(noticeLimit).map { item($0, nil) }
    }

    private static func explanation(for element: ModelElement, among texts: [ModelElement]) -> String? {
        guard let frame = element.frame else { return nil }
        return texts
            .compactMap { text -> (label: String, distance: CGFloat)? in
                guard let other = text.frame, other != frame, !text.label.isEmpty else { return nil }
                let distance = max(other.minY - frame.maxY, frame.minY - other.maxY, 0) + abs(other.midX - frame.midX) * 0.1
                return distance <= explanationReach ? (text.label, distance) : nil
            }
            .min { $0.distance < $1.distance }?
            .label
    }

    private static func ranked(_ elements: [ModelElement]) -> [ModelElement] {
        elements.enumerated()
            .sorted { ($0.element.salience, -$0.offset) > ($1.element.salience, -$1.offset) }
            .map(\.element)
    }

    private static func prominent(_ elements: [ModelElement]) -> [ModelElement] {
        elements.filter(\.visible) + elements.filter { !$0.visible }
    }

    private static func grouped(_ elements: [ModelElement], item: (ModelElement, String?) -> Item) -> [Item] {
        var order: [String] = []
        var groups: [String: (first: ModelElement, count: Int)] = [:]
        for element in elements {
            let key = "\(element.role.rawValue)|\(element.name.matchKey.numberless)"
            if let group = groups[key] {
                groups[key] = (group.first, group.count + 1)
            } else {
                groups[key] = (element, 1)
                order.append(key)
            }
        }
        return order.compactMap { groups[$0] }.map { group in
            var entry = item(group.first, nil)
            entry.similar = group.count - 1
            return entry
        }
    }

    private static func isPrimary(_ element: ModelElement) -> Bool {
        switch element.role {
        case .button, .menuitem, .switch: true
        case .link: element.hasPrimaryVerb
        default: false
        }
    }

    private static func isNotice(_ text: String) -> Bool {
        guard text.count <= noticeLength else { return false }
        let words = " " + text.matchKey.replacingOccurrences(of: "’", with: "'").filter { $0.isLetter || $0 == " " || $0 == "'" } + " "
        return noticePhrases.contains { words.contains(" \($0) ") }
    }

    private static let noticeLength = 200
    private static let noticePhrases = [
        "error", "failed", "failure", "invalid", "warning", "action required", "can't", "cannot", "unable", "not allowed",
        "denied", "only the", "expired", "suspended", "rejected", "try again", "problem"
    ]
}

private extension ElementRole {
    var isField: Bool {
        switch self {
        case .textbox, .textarea, .select, .checkbox, .radio, .switch, .slider: true
        default: false
        }
    }
}

extension ModelElement {
    var hasPrimaryVerb: Bool {
        let key = label.matchKey
        return Self.primaryVerbs.contains { key == $0 || key.hasPrefix($0 + " ") }
    }

    var salience: Int {
        let verbs = hasPrimaryVerb ? 3 : 0
        let kind = role == .button ? 2 : 0
        let placed = visible ? 4 : 0
        return verbs + kind + placed
    }

    private static let primaryVerbs = [
        "save", "submit", "next", "continue", "create", "publish", "send", "confirm", "sign in", "log in", "sign up", "done",
        "apply", "add", "start", "get started", "review", "update", "upload", "buy", "pay", "accept", "agree", "release",
        "roll out", "finish", "ok", "yes", "allow", "load", "open", "new", "edit", "delete", "remove", "discard", "cancel", "close"
    ]
}
