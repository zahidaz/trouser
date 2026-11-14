import Foundation

@MainActor
struct RouteReplay {
    let session: ProfileSession
    let query: String

    private var summary: String {
        "path “\(query)”"
    }

    func run() async -> Response {
        guard let tab = session.selectedTab, let start = session.signature(of: tab) else {
            return .failure("\(summary): no open page")
        }
        guard let route = session.atlas.atlas.route(from: start, to: query) else {
            return await stopped("no known path from \(start.description); use the site once with tap or set to teach it")
        }
        switch await session.supervisor.authorize(.view, "read page model for \(summary)") {
        case .granted(let entry): session.supervisor.finish(entry, .done)
        case .refused(let reason): return .failure("\(summary): \(reason)")
        }
        var done: [String] = []
        for (index, step) in route.enumerated() {
            let position = "step \(index + 1) of \(route.count)"
            guard let tab = session.selectedTab, let page = session.signature(of: tab), page == step.from else {
                return await stopped("\(position): expected \(step.from.description), found \(currentDescription)", done: done)
            }
            guard let element = try? await control(labeled: step.label, in: tab) else {
                return await stopped("\(position): “\(step.label)” is not on the page", done: done)
            }
            let response = await session.actions.perform(.act(ElementCommand(id: element.id, operation: .tap)), options: ActionOptions(quiet: true))
            guard response.ok else { return .failure((done + [response.message]).joined(separator: "\n")) }
            done.append(response.message.split(separator: "\n").first.map(String.init) ?? response.message)
        }
        guard route.last.map({ $0.to == current }) ?? true else {
            return await stopped("expected \(route.last?.to.description ?? "") after \(route.count) steps, found \(currentDescription)", done: done)
        }
        return .success(([route.isEmpty ? "\(summary): already there" : "\(summary): \(route.count) step\(route.count == 1 ? "" : "s")"] + done + [await brief]).joined(separator: "\n"))
    }

    private var current: PageSignature? {
        session.selectedTab.flatMap(session.signature(of:))
    }

    private var currentDescription: String {
        current?.description ?? "no page"
    }

    private var brief: String {
        get async {
            await session.actions.perform(.brief(json: false)).message
        }
    }

    private func control(labeled label: String, in tab: BrowserWindowController) async throws -> ModelElement? {
        let key = label.matchKey
        let matches = try await tab.pageModel.current().elements.filter {
            ($0.source == .dom || $0.role == .link) && $0.role.isActionable && $0.label.matchKey == key
        }
        return matches.first { $0.visible && !$0.states.contains(.disabled) } ?? matches.first
    }

    private func stopped(_ reason: String, done: [String] = []) async -> Response {
        .failure((["\(summary): stopped: \(reason)"] + done + [await brief]).joined(separator: "\n"))
    }
}
