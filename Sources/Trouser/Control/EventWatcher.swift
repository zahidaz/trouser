@MainActor
struct EventWatcher {
    let events: EventBus
    let options: WatchOptions

    func run(output: Output) async -> Response {
        var cursor = options.since ?? events.lastSequence
        var printed = 0
        while !Task.isCancelled {
            for event in events.events(after: cursor) {
                cursor = event.sequence
                guard options.includes(event) else { continue }
                output(options.render(event))
                printed += 1
                if options.stops(at: event) || printed == options.count {
                    return .success("")
                }
            }
            await events.next(within: .seconds(10))
        }
        return .success("")
    }
}
