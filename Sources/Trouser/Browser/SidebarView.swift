import SwiftUI

struct SidebarView: View {
    let session: ProfileSession

    var body: some View {
        List(selection: selection) {
            Section("Tabs") {
                ForEach(session.tabs, id: \.self) { tab in
                    TabRow(state: tab.state) { tab.close() }
                        .tag(ObjectIdentifier(tab))
                }
            }
            ForEach(HistoryDay.group(session.history.visits)) { day in
                Section(day.title) {
                    ForEach(day.visits) { visit in
                        Button {
                            session.selectedTab?.load(visit.url)
                        } label: {
                            Label {
                                Text(visit.title).lineLimit(1)
                            } icon: {
                                SiteIcon(url: visit.url, size: 16)
                            }
                        }
                        .buttonStyle(.plain)
                        .help(visit.url.absoluteString)
                        .contextMenu {
                            Button("Remove from History") { session.history.remove(visit.url) }
                            Button("Clear History") { session.history.removeAll() }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Label(session.name, systemImage: "person.crop.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var selection: Binding<ObjectIdentifier?> {
        Binding(
            get: { session.selectedTab.map(ObjectIdentifier.init) },
            set: { id in
                guard let tab = session.tabs.first(where: { ObjectIdentifier($0) == id }) else { return }
                session.select(tab)
            }
        )
    }
}

private struct TabRow: View {
    let state: TabState
    let close: () -> Void
    @State private var isHovered = false

    var body: some View {
        Label {
            HStack {
                Text(state.title).lineLimit(1)
                Spacer(minLength: 0)
                if isHovered {
                    Button(action: close) {
                        Image(systemName: "xmark").font(.caption2.weight(.bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Close Tab")
                }
            }
        } icon: {
            SiteIcon(url: state.url, size: 16)
        }
        .onHover { isHovered = $0 }
    }
}

private struct HistoryDay: Identifiable {
    let title: String
    let visits: [HistoryStore.Visit]

    var id: String { title }

    static func group(_ visits: [HistoryStore.Visit]) -> [HistoryDay] {
        let calendar = Calendar.current
        let titles = visits.map { visit in
            if calendar.isDateInToday(visit.date) { return "Today" }
            if calendar.isDateInYesterday(visit.date) { return "Yesterday" }
            return "Earlier"
        }
        return ["Today", "Yesterday", "Earlier"].compactMap { title in
            let matching = zip(visits, titles).filter { $0.1 == title }.map(\.0)
            return matching.isEmpty ? nil : HistoryDay(title: title, visits: Array(matching.prefix(50)))
        }
    }
}
