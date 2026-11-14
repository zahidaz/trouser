import Foundation
import Observation

@MainActor
@Observable
final class EventBus {
    private struct Subscriber {
        let continuation: CheckedContinuation<Void, Never>
        let timer: Task<Void, Never>
    }

    let profile: String
    private(set) var log: EventLog
    @ObservationIgnored private(set) var lastReaction: ContinuousClock.Instant?
    @ObservationIgnored private var subscribers: [UUID: Subscriber] = [:]

    static let capacity = 500

    init(profile: String, capacity: Int = EventBus.capacity) {
        self.profile = profile
        log = EventLog(capacity: capacity)
    }

    var lastSequence: Int {
        log.lastSequence
    }

    func emit(_ type: EventType, tab: Int? = nil, _ fields: [String: String] = [:]) {
        log.append(type, profile: profile, tab: tab, fields: fields)
        if type.isPageReaction {
            lastReaction = .now
        }
        let woken = subscribers
        subscribers.removeAll()
        woken.values.forEach { subscriber in
            subscriber.timer.cancel()
            subscriber.continuation.resume()
        }
    }

    func events(after sequence: Int) -> [Event] {
        log.events(after: sequence)
    }

    func next(within timeout: Duration) async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume()
                    return
                }
                let timer = Task { [weak self] in
                    try? await Task.sleep(for: timeout)
                    self?.wake(id)
                }
                subscribers[id] = Subscriber(continuation: continuation, timer: timer)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.wake(id) }
        }
    }

    private func wake(_ id: UUID) {
        guard let subscriber = subscribers.removeValue(forKey: id) else { return }
        subscriber.timer.cancel()
        subscriber.continuation.resume()
    }
}
