import Foundation

enum PreciseMapping {
    static func elements(_ snapshot: PreciseSnapshot, viewport: CGSize) -> [ModelElement] {
        let mapped = snapshot.nodes.compactMap { node in element(node, viewport: viewport).map { (node: node, element: $0) } }
        let containers = Set(snapshot.nodes.filter { textContainers.contains($0.role) }.map(\.key))
        let controlLabels = Set(mapped.filter { $0.element.role != .text }.map(\.element.label.matchKey))
        return mapped.compactMap { node, element in
            guard element.role == .text else { return element }
            let absorbed = node.parent.map(containers.contains) ?? false
            guard !absorbed, !element.offscreen, !controlLabels.contains(element.label.matchKey) else { return nil }
            return element
        }
    }

    static func element(_ node: PreciseNode, viewport: CGSize) -> ModelElement? {
        guard let role = role(of: node) else { return nil }
        let label = label(of: node, role: role)
        guard !label.isEmpty || role.showsValue || role == .checkbox || role == .radio || role == .switch else { return nil }
        var element = ModelElement(
            role: role,
            label: label,
            value: value(of: node, role: role),
            placeholder: node.placeholder.flatMap { $0.matchKey == label.matchKey ? nil : $0 },
            states: states(of: node, role: role),
            frame: node.rect,
            url: node.url.flatMap(URL.init(string:)),
            source: role == .text ? .text : .dom
        )
        element.identity = node.identity
        element.offscreen = node.rect.map { !CGRect(origin: .zero, size: viewport).intersects($0) } ?? false
        return element
    }

    static func role(of node: PreciseNode) -> ElementRole? {
        switch (node.role, node.subrole) {
        case ("AXButton", "AXSwitch"), ("AXCheckBox", "AXSwitch"): .switch
        case ("AXButton", _), ("AXMenuButton", _), ("AXDisclosureTriangle", _): .button
        case ("AXLink", _): .link
        case ("AXTextField", _), ("AXSearchField", _): .textbox
        case ("AXTextArea", _): .textarea
        case ("AXCheckBox", _): .checkbox
        case ("AXRadioButton", "AXTabButton"), ("AXTab", _): .tab
        case ("AXRadioButton", _): .radio
        case ("AXPopUpButton", _), ("AXComboBox", _): .select
        case ("AXSlider", _), ("AXIncrementor", _): .slider
        case ("AXMenuItem", _): .menuitem
        case ("AXHeading", _): .heading
        case ("AXStaticText", _): .text
        case ("AXImage", _): .image
        default: nil
        }
    }

    static func texts(_ elements: [ModelElement]) -> [PageElement] {
        elements.compactMap { element in
            guard element.visible, let frame = element.frame else { return nil }
            let text = element.role.showsValue ? element.value ?? element.label : element.label
            guard !text.isEmpty else { return nil }
            return PageElement(text: text, frame: frame, link: element.url)
        }
    }

    private static func label(of node: PreciseNode, role: ElementRole) -> String {
        let candidates = role == .text ? [node.value] : [node.title, node.description, role.showsValue ? nil : node.value]
        let text = candidates.compactMap { $0 }.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func value(of node: PreciseNode, role: ElementRole) -> String? {
        switch role {
        case .textbox, .textarea, .select: node.value.flatMap { $0.isEmpty ? nil : $0 }
        case .slider: node.number.map { $0.rounded() == $0 ? String(Int($0)) : String($0) } ?? node.value
        default: nil
        }
    }

    private static func states(of node: PreciseNode, role: ElementRole) -> [ElementState] {
        var states: [ElementState] = []
        if node.disabled == true { states.append(.disabled) }
        if [.checkbox, .radio, .switch].contains(role) {
            if node.number == 1 { states.append(.checked) }
            if node.number == 2 { states.append(.mixed) }
        }
        if let expanded = node.expanded, role != .select { states.append(expanded ? .expanded : .collapsed) }
        if node.selected == true || (role == .tab && node.number == 1) { states.append(.selected) }
        if node.required == true { states.append(.required) }
        if node.readonly == true { states.append(.readonly) }
        if node.invalid == true { states.append(.invalid) }
        return states
    }

    private static let textContainers: Set<String> = ["AXLink", "AXButton", "AXHeading", "AXMenuItem", "AXStaticText", "AXTab", "AXRadioButton", "AXCheckBox", "AXMenuButton"]
}
