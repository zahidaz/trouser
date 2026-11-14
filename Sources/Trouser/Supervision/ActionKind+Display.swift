extension ActionKind {
    var symbol: String {
        switch self {
        case .view: "eye"
        case .navigate: "arrow.triangle.turn.up.right.circle"
        case .pointer: "cursorarrow.click"
        case .scroll: "arrow.up.and.down"
        case .keyboard: "keyboard"
        case .submit: "paperplane"
        case .download: "arrow.down.circle"
        }
    }

    var verb: String {
        switch self {
        case .view: "look at the page"
        case .navigate: "navigate"
        case .pointer: "click"
        case .scroll: "scroll"
        case .keyboard: "type"
        case .submit: "submit a form"
        case .download: "download a file"
        }
    }

    var detail: String {
        switch self {
        case .view: "Screenshots and page source"
        case .navigate: "Opening pages, tabs and history"
        case .pointer: "Clicking on the page"
        case .scroll: "Scrolling the page"
        case .keyboard: "Typing and key presses"
        case .submit: "Form submissions triggered by an action"
        case .download: "Files saved to Downloads by an action"
        }
    }
}
