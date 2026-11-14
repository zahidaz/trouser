import AppKit
import SwiftUI

struct AutomationView: View {
    let profile: String
    let supervisor: Supervisor
    let setPaused: (Bool) -> Void
    @State private var section = Section.actions

    private enum Section: String, CaseIterable {
        case actions = "Actions"
        case timeline = "Timeline"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(16)
            Divider()
            switch section {
            case .actions: actions
            case .timeline: TimelineView(events: supervisor.events)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if supervisor.entries.isEmpty {
            ContentUnavailableView(
                "No Activity",
                systemImage: "dot.radiowaves.left.and.right",
                description: Text("Commands sent with the trouser CLI to “\(profile)” appear here.")
            )
        } else {
            List(supervisor.entries.reversed()) { entry in
                EntryRow(entry: entry)
            }
            .listStyle(.inset)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(status.color).frame(width: 8, height: 8)
                Text(status.text).font(.headline)
                Spacer()
            }
            HStack {
                Button {
                    setPaused(!supervisor.policy.paused)
                } label: {
                    Label(
                        supervisor.policy.paused ? "Resume" : "Pause",
                        systemImage: supervisor.policy.paused ? "play.fill" : "pause.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                Button {
                    NSApp.sendAction(#selector(AppDelegate.showSettings(_:)), to: nil, from: nil)
                } label: {
                    Label("Permissions", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity)
                }
            }
            .controlSize(.large)
            Picker("Section", selection: $section) {
                ForEach(Section.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var status: (text: String, color: Color) {
        if supervisor.policy.paused { return ("Automation Paused", .red) }
        if supervisor.pendingEntry != nil { return ("Waiting for Approval", .orange) }
        if supervisor.isActing { return ("Automation Active", .blue) }
        return ("Automation Idle", .green)
    }
}

private struct EntryRow: View {
    let entry: Supervisor.Entry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: entry.kind.symbol)
                .foregroundStyle(color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.summary).lineLimit(2)
                Text("\(detail) · \(entry.date.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 3)
    }

    private var color: Color {
        switch entry.outcome {
        case .pending: .orange
        case .running: .blue
        case .done: .secondary
        case .denied, .blocked, .failed: .red
        }
    }

    private var detail: String {
        switch entry.outcome {
        case .pending: "Awaiting approval"
        case .running: "Running"
        case .done: "Done"
        case .denied: "Denied"
        case .blocked: "Blocked"
        case .failed(let reason): reason
        }
    }
}
