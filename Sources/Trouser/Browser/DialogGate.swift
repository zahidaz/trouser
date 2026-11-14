import Foundation

struct PageDialog: Equatable {
    let kind: String
    let message: String
}

struct DialogOpen: LocalizedError, Equatable {
    let dialog: PageDialog

    var errorDescription: String? {
        "a JavaScript \(dialog.kind) is open on the page (“\(dialog.message)”); the page answers nothing until you close it in the Trouser window"
    }
}

@MainActor
final class DialogGate {
    private(set) var open: PageDialog?
    private var readers: [UUID: CheckedContinuation<PageModel, Error>] = [:]

    func check() throws {
        if let open {
            throw DialogOpen(dialog: open)
        }
    }

    func show(_ dialog: PageDialog) {
        open = dialog
        let waiting = readers
        readers = [:]
        for reader in waiting.values {
            reader.resume(throwing: DialogOpen(dialog: dialog))
        }
    }

    func close() {
        open = nil
    }

    func value(of task: Task<PageModel, Error>) async throws -> PageModel {
        try check()
        let id = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            readers[id] = continuation
            Task {
                let result = await task.result
                readers.removeValue(forKey: id)?.resume(with: result)
            }
        }
    }
}
