import Foundation

enum SessionError: LocalizedError {
    case noTab(Int)

    var errorDescription: String? {
        switch self {
        case .noTab(let index): "there is no tab \(index)"
        }
    }
}

enum NavigationError: LocalizedError {
    case failed(String, page: String)

    var errorDescription: String? {
        switch self {
        case .failed(let reason, let page): "\(reason)\n\(page)"
        }
    }
}

@MainActor
struct ActionPipeline {
    let session: ProfileSession

    private var supervisor: Supervisor {
        session.supervisor
    }

    private var events: EventBus {
        session.events
    }

    func perform(_ requested: PageAction, options: ActionOptions = ActionOptions()) async -> Response {
        guard !supervisor.isBusy else { return .failure("busy: another action is running or awaiting approval") }
        guard let tab = session.selectedTab else { return .failure("no open tab") }
        if let dialog = tab.dialogs.open, !requested.leavesTab {
            return .failure("\(requested.summary): \(DialogOpen(dialog: dialog).localizedDescription)")
        }
        let action: PageAction
        let context: ActionContext
        do {
            action = try await resolve(requested, in: tab)
            try action.point.map(tab.driver.validate)
            context = ActionContext(host: tab.webView.url?.host(), label: try await targetLabel(of: action, in: tab))
        } catch {
            return .failure("\(requested.summary): \(error.localizedDescription)")
        }

        if let url = action.destination, let reason = session.fenceRefusal(for: url) {
            supervisor.refuse(.navigate, action.summary, reason: reason)
            return .failure("\(action.summary): blocked: \(reason)")
        }

        tab.marker.show(action.point, pending: supervisor.decision(for: action.kind, context: context).mode == .ask)
        defer { tab.marker.hide() }

        let entry: Supervisor.Entry.ID
        switch await supervisor.authorize(action.kind, action.summary, context: context) {
        case .granted(let id): entry = id
        case .refused(let reason): return .failure("\(action.summary): \(reason)")
        }

        tab.marker.show(action.point, pending: false)
        supervisor.beginAction()
        let response = await run(action, entry: entry, options: options, in: tab)
        if action.changesPage, session.selectedTab?.dialogs.open == nil {
            await LiveScreenshot.refresh(in: session)
        }
        let violations = supervisor.endAction()
        guard violations.isEmpty else {
            supervisor.finish(entry, .failed(violations.joined(separator: "; ")))
            let page = session.selectedTab?.driver.pageDescription ?? "no open tab"
            return .failure((["\(action.summary): stopped by a rule"] + violations + [page]).joined(separator: "\n"))
        }
        return response
    }

    private func run(_ action: PageAction, entry: Supervisor.Entry.ID, options: ActionOptions, in tab: BrowserWindowController) async -> Response {
        if action.kind == .pointer || action.kind == .keyboard {
            tab.driver.focus()
        }
        if action.changesPage {
            session.lastChange = nil
        }
        do {
            let before = tab.pageModel.baseline
            if let report = try await read(action, from: tab) {
                supervisor.finish(entry, .done)
                guard case .find = action else { return .success(report) }
                tab.pageModel.invalidate()
                let reply = ActionReply(summary: report, page: tab.driver.pageDescription)
                return .success(try await replying(reply, on: tab, before: before, after: .unchanged, quiet: options.quiet).text)
            }
            guard action.changesPage else {
                let file = try await capture(action, from: tab)
                supervisor.finish(entry, .done)
                return .success("\(action.summary): done\n\(tab.driver.pageDescription)", file: file)
            }
            var baseline = events.lastSequence
            let origin = session.signature(of: tab)
            guard let (acted, input) = try await apply(action, from: tab) else {
                supervisor.finish(entry, .done)
                return .success("\(action.summary): done")
            }
            var outcome = await settle(action, on: acted, since: input)
            if case .navigate(.url) = action, events.events(after: baseline).navigationFailure?.isConnectionLoss == true {
                baseline = events.lastSequence
                try acted.driver.perform(action)
                outcome = await settle(action, on: acted, since: .now)
            }
            if case .navigate = action, let failure = events.events(after: baseline).navigationFailure?.note {
                throw NavigationError.failed(failure, page: acted.driver.pageDescription)
            }
            let target = session.selectedTab ?? acted
            remember(action, from: origin, to: session.signature(of: target))
            guard target.webView.url != nil else {
                supervisor.finish(entry, .done)
                return .success("\(action.summary): done\nempty tab — open a URL with: trouser go <url>")
            }
            let reply = try await replying(
                ActionReply(summary: "\(action.summary): done", page: "", notes: events.events(after: baseline).compactMap(\.note)),
                on: target,
                before: target === tab ? before : target.pageModel.baseline,
                after: outcome,
                quiet: options.quiet
            )
            session.lastChange = reply.changed
            supervisor.finish(entry, .done)
            return .success(reply.text)
        } catch {
            supervisor.finish(entry, .failed(error.localizedDescription))
            return .failure("\(action.summary): \(error.localizedDescription)")
        }
    }

    private func settle(_ action: PageAction, on tab: BrowserWindowController, since input: ContinuousClock.Instant) async -> SettleOutcome {
        let expected = tab.pageModel.confirmed
        tab.pageModel.invalidate(focus: action.focusedElement)
        return await settler(on: tab, expecting: expected) { [supervisor] in tab.webView.isLoading || supervisor.pendingID != nil }
            .settle(.action, since: input, typed: action.typedLength)
    }

    private func settler(on tab: BrowserWindowController, expecting model: PageModel?, busy: @escaping () -> Bool) -> ActionSettler {
        ActionSettler(signals: PageSignals(events: events, proxy: session.proxy, busy: busy, probe: { try await tab.pageModel.refresh() }, expected: model))
    }

    private func replying(
        _ reply: ActionReply,
        on tab: BrowserWindowController,
        before: PageModel?,
        after outcome: SettleOutcome,
        quiet: Bool
    ) async throws -> ActionReply {
        var reply = reply
        if !quiet {
            let model = try await settler(on: tab, expecting: nil) { tab.webView.isLoading }
                .confirmedModel(after: outcome, changingFrom: before) { try await tab.pageModel.refresh() }
            tab.pageModel.record(model)
            let signals = briefSignals(for: tab)
            let brief = PageBrief(model: model, signals: signals)
            if let before, before.page.document == model.page.document {
                reply.changes = .diff(ModelDiff(from: before, to: model), brief: brief.delta(from: PageBrief(model: before, signals: signals)))
            } else {
                reply.changes = .page(brief)
            }
        }
        return ActionReply(summary: reply.summary, page: tab.driver.pageDescription, notes: reply.notes, changes: reply.changes)
    }

    private func remember(_ action: PageAction, from origin: PageSignature?, to reached: PageSignature?) {
        guard !session.isClosed, let label = action.pressedLabel, let origin, let reached else { return }
        session.atlas.record(from: origin, label: label, to: reached)
    }

    private func briefSignals(for tab: BrowserWindowController) -> PageBrief.Signals {
        PageBrief.Signals(
            approval: supervisor.pendingEntry?.summary,
            destinations: session.atlas.atlas.destinations(from: session.signature(of: tab))
        )
    }

    private func targetLabel(of action: PageAction, in tab: BrowserWindowController) async throws -> String? {
        guard case .click(let point, _) = action else { return action.targetLabel }
        return try await tab.label(at: point)
    }

    private func resolve(_ action: PageAction, in tab: BrowserWindowController) async throws -> PageAction {
        switch action {
        case .act(let command):
            return .act(try await tab.elementActions.resolve(command))
        case .intent(let intent):
            let destinations = session.atlas.atlas.destinations(from: session.signature(of: tab))
            let element = try await tab.pageModel.search { try IntentRanker.choose(intent, in: $0, destinations: destinations) }
            let operation: ElementCommand.Operation = intent.value.map { .set($0) } ?? .tap
            return .act(try await tab.elementActions.resolve(ElementCommand(id: element.id, operation: operation)))
        default:
            return action
        }
    }

    private func read(_ action: PageAction, from tab: BrowserWindowController) async throws -> String? {
        switch action {
        case .brief(let json):
            let model = try await tab.pageModel.snapshot()
            tab.pageModel.record(model)
            let brief = PageBrief(model: model, signals: briefSignals(for: tab))
            return json ? try brief.json() : brief.lines.joined(separator: "\n")
        case .state(let json, let recognizing):
            let model = recognizing ? try await tab.pageModel.refresh(recognizing: true) : try await tab.pageModel.snapshot()
            tab.pageModel.record(model)
            return json ? try model.json() : model.description
        case .query(let query):
            let matches = try await tab.pageModel.search { model in
                let matches = query.select(from: model.elements)
                guard !matches.isEmpty else { throw ModelError.noMatch }
                return matches
            }
            return matches.map(\.description).joined(separator: "\n")
        case .find(let text):
            return "found \(try await tab.pageModel.reveal(text).description)"
        default:
            return nil
        }
    }

    private func apply(_ action: PageAction, from tab: BrowserWindowController) async throws -> (BrowserWindowController, ContinuousClock.Instant)? {
        let start = ContinuousClock.now
        switch action {
        case .act(let command):
            return (tab, try await tab.elementActions.perform(command))
        case .tab(.new(let url)):
            return (session.newTab(url), start)
        case .tab(.close):
            tab.close()
            return session.selectedTab.map { ($0, start) }
        case .tab(.select(let index)):
            let tabs = session.tabs
            guard tabs.indices.contains(index - 1) else { throw SessionError.noTab(index) }
            session.select(tabs[index - 1])
            return (tabs[index - 1], start)
        case .drag(let origin, let target):
            try await tab.driver.drag(from: origin, to: target)
            return (tab, .now)
        default:
            try tab.driver.perform(action)
            return (tab, start)
        }
    }

    private func capture(_ action: PageAction, from tab: BrowserWindowController) async throws -> URL {
        if case .source(let all) = action {
            let archive = try await tab.driver.archive()
            guard all else {
                let file = try ControlPath.capture(for: session.name, extension: "html")
                try archive.main.data.write(to: file, options: .atomic)
                return file
            }
            return try archive.write(to: try ControlPath.capture(for: session.name, extension: "source"))
        }
        let file = try ControlPath.capture(for: session.name, extension: "png")
        try await tab.driver.screenshot(to: file, fullPage: action == .screenshot(fullPage: true))
        return file
    }
}
