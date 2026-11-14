import AppKit

@MainActor
final class CommandRouter {
    private let workspace: Workspace

    init(workspace: Workspace) {
        self.workspace = workspace
    }

    func handle(_ arguments: [String], output: Output) async -> Response {
        do {
            return await execute(try Command(arguments: arguments), output: output, since: Date())
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func execute(_ command: Command, output: Output, since: Date) async -> Response {
        do {
            switch command {
            case .status:
                return .success(workspace.status)
            case .open(let profile, let url):
                let session = if let profile {
                    try await workspace.open(profile)
                } else if let active = workspace.activeSession {
                    active
                } else {
                    try await workspace.openDefault()
                }
                guard let url else { return .success("opened \(session.name)") }
                return await session.actions.perform(.navigate(.url(url)))
            case .background(let background):
                workspace.setBackground(background)
                return .success(background ? "background mode on: windows hidden, approvals appear at the top right" : "background mode off: windows restored")
            case .downloads(let profile):
                return .success(try session(profile).downloads.summary)
            case .rules(let profile):
                let name = try existingProfile(profile ?? workspace.activeSession?.name ?? Workspace.defaultProfile)
                let report = RulesReport(
                    profile: name,
                    policy: workspace.policy,
                    store: try workspace.rules(for: name),
                    host: workspace.session(for: name)?.selectedTab?.webView.url?.host()
                )
                return .success(report.text)
            case .page(let profile, let action, let options):
                return try await session(profile).actions.perform(action, options: options)
            case .watch(let profile, let options):
                let name = try existingProfile(profile ?? workspace.activeProfile)
                return await EventWatcher(events: workspace.events(for: name), options: options).run(output: output)
            case .live(let profile, let every):
                return await LiveScreenshot(session: try session(profile), every: every).run(output: output)
            case .wait(let profile, let condition, let timeout):
                let session = try session(profile)
                return await PageWaiter(session: session, condition: condition, timeout: timeout).run(since: since)
            case .path(let profile, let query):
                return await RouteReplay(session: try session(profile), query: query).run()
            case .expect(let profile, let expectation):
                return await expectation.check(in: try session(profile))
            case .run(let steps):
                return await run(steps, output: output)
            case .network(let profile, let json, let hosts):
                let log = try session(profile).proxy.log
                switch (json, hosts) {
                case (true, true): return .success(try Reports.json(log.hosts))
                case (true, false): return .success(try Reports.json(log.records))
                case (false, true): return .success(Reports.hosts(log.hosts))
                case (false, false): return .success(Reports.connections(log.records, now: Date()))
                }
            case .privacy(let profile, let json):
                let report = await PrivacyInspector.report(for: try session(profile).dataStore)
                return .success(json ? try Reports.json(report) : Reports.privacy(report))
            case .deleteProfile(let rawName):
                let name = try existingProfile(rawName)
                guard name != Workspace.defaultProfile else { return .failure("the default profile can't be deleted") }
                guard workspace.confirmDeletion(of: name) else { return .failure("cancelled in Trouser: profile “\(name)” was kept") }
                try await workspace.deleteKeepingWindowOpen(name)
                return .success("deleted profile “\(name)”")
            case .profile(let profile):
                let session = try session(profile)
                return .success(Reports.settings(session.settings.settings, profile: session.name, ruleError: session.contentRuleError, precise: session.preciseReport))
            }
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func run(_ steps: [Command], output: Output) async -> Response {
        var previousStart = Date()
        for (index, step) in steps.enumerated() {
            let start = Date()
            let response = await execute(step, output: output, since: previousStart)
            let lines = [response.message] + (response.file.map { [$0] } ?? [])
            output("[\(index + 1)/\(steps.count)] " + lines.joined(separator: "\n"))
            guard response.ok else {
                return .failure("stopped at step \(index + 1) of \(steps.count)")
            }
            if case .wait = step {
                continue
            }
            previousStart = start
        }
        let page = (try? session(steps.last?.profile))?.selectedTab?.driver.pageDescription
        return .success("finished \(steps.count) steps" + (page.map { "\n\($0)" } ?? ""))
    }

    private func existingProfile(_ name: String) throws -> String {
        guard workspace.profileNames.contains(name) else {
            throw CommandError.invalid("no profile named “\(name)”")
        }
        return name
    }

    private func session(_ profile: String?) throws -> ProfileSession {
        guard let session = profile.map(workspace.session(for:)) ?? workspace.activeSession else {
            throw CommandError.invalid("no open profile; run: \(profile.map { "trouser -p \($0) open" } ?? "trouser open")")
        }
        return session
    }
}
