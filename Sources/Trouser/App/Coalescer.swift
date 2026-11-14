@MainActor
final class Coalescer {
    private let delay: Duration
    private let action: @MainActor () async -> Void
    private var pending: Task<Void, Never>?

    init(delay: Duration, action: @escaping @MainActor () async -> Void) {
        self.delay = delay
        self.action = action
    }

    func schedule() {
        guard pending == nil else { return }
        pending = Task { [weak self, delay] in
            try? await Task.sleep(for: delay)
            guard let self else { return }
            pending = nil
            await action()
        }
    }
}
