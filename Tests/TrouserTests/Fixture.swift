import Foundation
@testable import Trouser

enum Fixture {
    static func element(
        _ role: ElementRole,
        _ label: String,
        value: String? = nil,
        x: CGFloat = 10,
        y: CGFloat? = 100,
        states: [ElementState] = [],
        source: ElementSource = .dom
    ) -> ModelElement {
        ModelElement(role: role, label: label, value: value, states: states, frame: y.map { CGRect(x: x, y: $0, width: 80, height: 20) }, source: source)
    }

    static func model(_ elements: [ModelElement], title: String = "Listing", url: String = "https://shop.example.com/admin", focus: String? = nil) -> PageModel {
        let info = PageInfo(
            url: URL(string: url),
            title: title,
            loading: false,
            progress: 1,
            secure: true,
            onlySecureContent: true,
            generation: 3,
            viewport: CGSize(width: 1280, height: 860)
        )
        return PageModel(page: info, focus: focus, elements: elements)
    }
}
