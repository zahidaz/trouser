import Foundation
import Testing
@testable import Trouser

@MainActor
struct DialogGateTests {
    private let dialog = PageDialog(kind: "alert", message: "Saved")

    @Test func readsFailAtOnceWhileADialogIsOpen() async {
        let gate = DialogGate()
        gate.show(dialog)
        #expect(throws: DialogOpen(dialog: dialog)) { try gate.check() }
        gate.close()
        #expect(throws: Never.self) { try gate.check() }
    }

    @Test func aDialogEndsAReadThatThePageWillNotAnswer() async {
        let gate = DialogGate()
        let unanswered = Task<PageModel, Error> {
            try await Task.sleep(for: .seconds(60))
            throw CancellationError()
        }
        defer { unanswered.cancel() }
        Task {
            try await Task.sleep(for: .milliseconds(20))
            gate.show(dialog)
        }
        await #expect(throws: DialogOpen(dialog: dialog)) { try await gate.value(of: unanswered) }
    }

    @Test func namesTheDialogAndWhereToAnswerIt() {
        #expect(DialogOpen(dialog: dialog).localizedDescription == "a JavaScript alert is open on the page (“Saved”); the page answers nothing until you close it in the Trouser window")
    }
}
