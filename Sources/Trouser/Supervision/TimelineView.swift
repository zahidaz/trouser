import SwiftUI

struct TimelineView: View {
    let events: EventBus
    @State private var category: String?

    var body: some View {
        VStack(spacing: 0) {
            Picker("Show", selection: $category) {
                Text("All Events").tag(String?.none)
                Divider()
                ForEach(EventType.categories, id: \.self) { category in
                    Label(category.capitalized, systemImage: Self.symbol(for: category)).tag(Optional(category))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            if shown.isEmpty {
                ContentUnavailableView(
                    "No Events",
                    systemImage: "waveform.path.ecg",
                    description: Text("Page, navigation, download and automation events appear here as they happen.")
                )
            } else {
                List(shown) { event in
                    EventRow(event: event)
                }
                .listStyle(.inset)
            }
        }
    }

    private var shown: [Event] {
        events.log.events.reversed().filter { category == nil || $0.type.category == category }
    }

    static func symbol(for category: String) -> String {
        switch category {
        case "navigation": "arrow.triangle.turn.up.right.circle"
        case "page": "doc.richtext"
        case "ui": "macwindow"
        case "download": "arrow.down.circle"
        case "cookies": "tray.2"
        default: "gearshape.2"
        }
    }
}

private struct EventRow: View {
    let event: Event

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: TimelineView.symbol(for: event.type.category))
                .foregroundStyle(isFailure ? .red : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.type.rawValue).font(.callout.monospaced())
                if !details.isEmpty {
                    Text(details).font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                }
                Text("#\(event.sequence)\(event.tab.map { " · tab \($0)" } ?? "") · \(event.date.formatted(date: .omitted, time: .standard))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private var isFailure: Bool {
        [.navigationFailed, .downloadFailed, .actionFailed, .actionDenied, .actionBlocked, .processTerminated].contains(event.type)
    }

    private var details: String {
        event.fields.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: " · ")
    }
}
