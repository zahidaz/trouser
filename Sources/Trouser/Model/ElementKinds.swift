import Foundation

enum ElementRole: String, CaseIterable, Codable {
    case button, link, textbox, textarea, checkbox, radio, select, slider, tab, menuitem, option, `switch`, heading, text, image, dialog, alert

    var isFillable: Bool {
        self == .textbox || self == .textarea
    }

    var showsValue: Bool {
        isFillable || self == .select
    }

    var isActionable: Bool {
        switch self {
        case .heading, .text, .image, .dialog, .alert: false
        default: true
        }
    }

    var isContainer: Bool {
        self == .dialog || self == .alert
    }
}

enum ElementState: String, CaseIterable, Codable {
    case disabled, checked, mixed, expanded, collapsed, selected, required, readonly, invalid
}

enum ElementSource: String, Codable {
    case dom, text, ocr
}
