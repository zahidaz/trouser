import Foundation

struct DOMControl: Equatable {
    let role: ElementRole
    let label: String
    var value: String?
    var placeholder: String?
    var states: [ElementState] = []
    var url: URL?
    var context: String?
    var secret = false
    var drawsLabel = true
}

enum PageControls {
    static func controls(inHTML html: String, base: URL? = nil) throws -> [DOMControl] {
        let document = try XMLDocument(xmlString: tidyable(html), options: [.documentTidyHTML])
        var scan = Scan()
        document.rootElement().map { scan.visit($0, hidden: false) }
        return scan.candidates.compactMap { candidate in
            let element = candidate.element
            guard let role = role(of: element) else { return nil }
            let label = label(of: element, role: role, scan: scan)
            let context = role.isActionable ? context(of: candidate, excluding: label) : nil
            guard !label.isEmpty || context != nil else { return nil }
            return DOMControl(
                role: role,
                label: label,
                value: value(of: element, role: role),
                placeholder: attribute("placeholder", of: element).map(clean).flatMap(nonEmpty),
                states: states(of: element, role: role),
                url: role == .link ? attribute("href", of: element).flatMap { URL(string: $0, relativeTo: base)?.absoluteURL } : nil,
                context: context,
                secret: isSecret(element),
                drawsLabel: drawsLabel(label, of: element, role: role)
            )
        }
    }

    private struct Candidate {
        let element: XMLElement
        let row: XMLElement?
        let heading: String?
    }

    private static func context(of candidate: Candidate, excluding label: String) -> String? {
        let rowText = candidate.row.map { row in
            clean((row.stringValue ?? "").replacingOccurrences(of: label, with: " ", options: [], range: nil))
        }
        let text = [rowText, candidate.heading].compactMap { $0 }.first { !$0.isEmpty }
        return text.map { String($0.prefix(contextLength)) }
    }

    private static let contextLength = 60
    static let secretValue = "••••"
    private static let rowRoles: Set<String> = ["row", "listitem"]

    private struct Scan {
        var candidates: [Candidate] = []
        var labels: [String: String] = [:]
        var identified: [String: XMLElement] = [:]
        private var heading: String?

        mutating func visit(_ element: XMLElement, hidden: Bool, row: XMLElement? = nil) {
            let name = element.name?.lowercased() ?? ""
            let hidden = hidden || element.attribute(forName: "hidden") != nil || attribute("aria-hidden", of: element) == "true"
            if let id = attribute("id", of: element) {
                identified[id] = element
            }
            if name == "label", let target = attribute("for", of: element) {
                labels[target] = clean(element.stringValue ?? "")
            }
            if !hidden, isCandidate(element, name: name) {
                candidates.append(Candidate(element: element, row: row, heading: heading))
                if role(of: element) == .heading {
                    heading = clean(element.stringValue ?? "")
                }
            }
            guard name != "template" else { return }
            let isRow = name == "tr" || name == "li" || attribute("role", of: element).map(rowRoles.contains) == true
            for case let child as XMLElement in element.children ?? [] {
                visit(child, hidden: hidden, row: isRow ? element : row)
            }
        }

        func text(of id: String) -> String? {
            identified[id].map { clean($0.stringValue ?? "") }
        }

        private func isCandidate(_ element: XMLElement, name: String) -> Bool {
            switch name {
            case "button", "textarea", "select", "h1", "h2", "h3", "h4", "h5", "h6": return true
            case "a" where element.attribute(forName: "href") != nil: return true
            case "input" where attribute("type", of: element) != "hidden": return true
            case "img" where element.attribute(forName: "alt") != nil: return true
            default: return attribute("role", of: element).map { ariaRoles[$0] != nil } ?? false
            }
        }
    }

    static func tidyable(_ html: String) -> String {
        let range = NSRange(html.startIndex..., in: html)
        return unknownTags.stringByReplacingMatches(in: html, range: range, withTemplate: "<$1div")
    }

    private static let unknownTags = try! NSRegularExpression(
        pattern: "<(/?)(?:[a-z][a-z0-9]*-[a-z0-9-]*|header|footer|main|nav|section|article|aside|figure|figcaption|dialog|search|hgroup)(?=[\\s/>])",
        options: [.caseInsensitive]
    )

    private static let ariaRoles: [String: ElementRole] = [
        "button": .button, "link": .link, "checkbox": .checkbox, "radio": .radio, "tab": .tab,
        "menuitem": .menuitem, "menuitemcheckbox": .menuitem, "menuitemradio": .menuitem, "option": .option,
        "switch": .switch, "combobox": .select, "listbox": .select, "textbox": .textbox, "searchbox": .textbox,
        "slider": .slider, "heading": .heading, "img": .image,
        "dialog": .dialog, "alertdialog": .dialog, "alert": .alert, "status": .alert
    ]

    private static func role(of element: XMLElement) -> ElementRole? {
        if let role = attribute("role", of: element).flatMap({ ariaRoles[$0.lowercased()] }) {
            if role == .select, let typed = typedRole(of: element) {
                return typed
            }
            return role == .textbox && attribute("aria-multiline", of: element) == "true" ? .textarea : role
        }
        switch element.name?.lowercased() {
        case "a": return .link
        case "button": return .button
        case "textarea": return .textarea
        case "select": return .select
        case "img": return .image
        case "h1", "h2", "h3", "h4", "h5", "h6": return .heading
        case "input":
            switch attribute("type", of: element)?.lowercased() {
            case "checkbox": return .checkbox
            case "radio": return .radio
            case "range": return .slider
            case "submit", "button", "reset", "image", "file": return .button
            default: return .textbox
            }
        default: return nil
        }
    }

    private static func typedRole(of element: XMLElement) -> ElementRole? {
        switch element.name?.lowercased() {
        case "textarea": .textarea
        case "input": textInputTypes.contains(attribute("type", of: element)?.lowercased() ?? "text") ? .textbox : nil
        default: attribute("contenteditable", of: element).map { $0 != "false" } == true ? .textbox : nil
        }
    }

    private static let textInputTypes: Set<String> = ["text", "search", "email", "url", "tel", "number", "password"]

    private static func label(of element: XMLElement, role: ElementRole, scan: Scan) -> String {
        let labelledBy = attribute("aria-labelledby", of: element)?
            .split(separator: " ")
            .compactMap { scan.text(of: String($0)) }
            .joined(separator: " ")
        let wrapping = ancestorLabel(of: element)
        let isInput = element.name?.lowercased() == "input"
        let ownText = role.isFillable || role == .select ? nil : element.stringValue
        let candidates = [
            attribute("aria-label", of: element),
            labelledBy,
            attribute("id", of: element).flatMap { scan.labels[$0] },
            wrapping,
            ownText,
            attribute("alt", of: element),
            attribute("placeholder", of: element),
            isInput && role == .button ? attribute("value", of: element) : nil,
            attribute("title", of: element),
            attribute("name", of: element)
        ]
        let text = candidates.compactMap { $0 }.map(clean).first { !$0.isEmpty } ?? ""
        return String(text.prefix(120))
    }

    private static func drawsLabel(_ label: String, of element: XMLElement, role: ElementRole) -> Bool {
        guard !role.showsValue, !label.isEmpty else { return true }
        let classes = Set((attribute("class", of: element) ?? "").lowercased().split(separator: " ").map(String.init))
        guard classes.isDisjoint(with: screenReaderClasses) else { return false }
        if element.name?.lowercased() == "input" {
            return true
        }
        return clean(element.stringValue ?? "").matchKey.contains(label.matchKey)
    }

    private static let screenReaderClasses: Set<String> = ["visually-hidden", "visuallyhidden", "sr-only", "screen-reader-text", "screen-reader-only", "a11y-hidden"]

    private static func value(of element: XMLElement, role: ElementRole) -> String? {
        switch element.name?.lowercased() {
        case "textarea":
            return nonEmpty(clean(element.stringValue ?? ""))
        case "select":
            let options = element.elements(forName: "option") + element.elements(forName: "optgroup").flatMap { $0.elements(forName: "option") }
            let selected = options.first { $0.attribute(forName: "selected") != nil } ?? options.first
            return selected.flatMap { nonEmpty(clean($0.stringValue ?? "")) }
        case "input" where isSecret(element):
            return attribute("value", of: element).flatMap(nonEmpty).map { _ in secretValue }
        case "input" where role.isFillable || role == .slider:
            return attribute("value", of: element).map(clean).flatMap(nonEmpty)
        default:
            return nil
        }
    }

    private static func states(of element: XMLElement, role: ElementRole) -> [ElementState] {
        func flag(_ name: String) -> Bool {
            element.attribute(forName: name) != nil
        }
        func aria(_ name: String) -> String? {
            attribute("aria-\(name)", of: element)?.lowercased()
        }
        var states: Set<ElementState> = []
        if flag("disabled") || aria("disabled") == "true" { states.insert(.disabled) }
        if flag("checked") || aria("checked") == "true" || aria("pressed") == "true" || styledChecked(element, role: role) {
            states.insert(.checked)
        }
        if aria("checked") == "mixed" { states.insert(.mixed) }
        if aria("expanded") == "true" { states.insert(.expanded) }
        if aria("expanded") == "false" { states.insert(.collapsed) }
        if flag("selected") || aria("selected") == "true" { states.insert(.selected) }
        if flag("required") || aria("required") == "true" { states.insert(.required) }
        if flag("readonly") || aria("readonly") == "true" { states.insert(.readonly) }
        if aria("invalid") == "true" { states.insert(.invalid) }
        return ElementState.allCases.filter(states.contains)
    }

    private static func styledChecked(_ element: XMLElement, role: ElementRole) -> Bool {
        guard [.checkbox, .radio, .switch].contains(role) else { return false }
        var node: XMLNode? = element
        for _ in 0..<checkedClassDepth {
            guard let current = node as? XMLElement else { return false }
            let classes = attribute("class", of: current)?.split(separator: " ") ?? []
            if classes.contains(where: { $0.hasSuffix("-checked") || $0.hasSuffix("--selected") }) {
                return true
            }
            node = current.parent
        }
        return false
    }

    private static let checkedClassDepth = 4

    private static func ancestorLabel(of element: XMLElement) -> String? {
        var parent = element.parent
        while let node = parent {
            if let label = node as? XMLElement, label.name?.lowercased() == "label" {
                return label.stringValue
            }
            parent = node.parent
        }
        return nil
    }

    private static func attribute(_ name: String, of element: XMLElement) -> String? {
        element.attribute(forName: name)?.stringValue
    }

    private static func clean(_ text: String) -> String {
        text.withoutPrivateUse.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func isSecret(_ element: XMLElement) -> Bool {
        element.name?.lowercased() == "input" && attribute("type", of: element)?.lowercased() == "password"
    }

    private static func nonEmpty(_ text: String) -> String? {
        text.isEmpty ? nil : text
    }
}
