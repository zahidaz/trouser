@MainActor
func awaitingAtMost(_ duration: Duration, _ operation: @escaping @MainActor () async -> Void) async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        var finished = false
        let finish = {
            guard !finished else { return }
            finished = true
            continuation.resume()
        }
        Task {
            await operation()
            finish()
        }
        Task {
            try? await Task.sleep(for: duration)
            finish()
        }
    }
}
