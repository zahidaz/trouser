import AppKit
import Testing
@testable import Trouser

@MainActor
struct AddressFieldTests {
    @Test func trailingButtonReloadsThePage() throws {
        let button = try #require((AddressField().cell as? NSSearchFieldCell)?.cancelButtonCell)
        #expect(button.action == #selector(BrowserWindowController.reload(_:)))
        #expect(button.target == nil)
        #expect(button.accessibilityLabel() == "Reload Page")
    }
}
