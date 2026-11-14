import Foundation

@MainActor
struct PageWaiter {
    let session: ProfileSession
    let condition: WaitCondition
    let timeout: Duration

    func run(since: Date) async -> Response {
        if let refusal = await refusal(for: "wait for") {
            return refusal
        }
        let start = ContinuousClock.now
        let deadline = start + timeout
        while true {
            let state = await snapshot(since: since, start: start)
            if condition.holds(in: state) {
                let elapsed = ContinuousClock.now - start
                let page = session.selectedTab?.driver.pageDescription ?? "no open tab"
                return .success("\(condition.summary) after \(Int(elapsed / .milliseconds(1))) ms\n\(page)")
            }
            let now = ContinuousClock.now
            guard now < deadline, !Task.isCancelled else {
                return .failure("timed out after \(String(format: "%g", timeout / .seconds(1))) s waiting for \(condition.summary)")
            }
            await session.events.next(within: min(deadline - now, condition.recheck(after: state)))
        }
    }

    func check() async -> Response {
        if let refusal = await refusal(for: "expect") {
            return refusal
        }
        let page = session.selectedTab?.driver.pageDescription ?? "no open tab"
        guard condition.holds(in: await snapshot(since: Date(), start: .now)) else {
            return .failure("expected \(condition.summary), not found\n\(page)")
        }
        return .success("\(condition.summary): as expected")
    }

    private func refusal(for verb: String) async -> Response? {
        guard condition.readsPage else { return nil }
        switch await session.supervisor.authorize(.view, "\(verb) \(condition.summary)") {
        case .granted(let entry):
            session.supervisor.finish(entry, .done)
            return nil
        case .refused(let reason):
            return .failure("\(verb) \(condition.summary): \(reason)")
        }
    }

    private func snapshot(since: Date, start: ContinuousClock.Instant) async -> WaitCondition.State {
        let tab = session.selectedTab
        let isLoading = tab?.webView.isLoading ?? false
        var settling = Settling(.idle(within: timeout), start: start)
        let signals = PageSignals(events: session.events, proxy: session.proxy) { isLoading }
        var state = WaitCondition.State(isLoading: isLoading, url: tab?.webView.url, idle: settling.next(signals.observe()))
        if case .event = condition {
            state.events = session.events.log.events.filter { $0.date >= since }
        }
        if condition.readsPage, let tab {
            state.elements = (try? await tab.pageModel.visibleTexts()) ?? []
        }
        return state
    }
}
