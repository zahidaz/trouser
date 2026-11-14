import SwiftUI

struct PrivacyDashboardView: View {
    let workspace: Workspace
    let profile: String
    @State private var report: PrivacyReport?
    @State private var hosts: [HostSummary] = []
    @State private var pendingRemoval: PrivacyReport.Site?

    private static let hostLimit = 50

    var body: some View {
        Form {
            Section {
                if let report {
                    if report.sites.isEmpty {
                        Text("No website data stored.").foregroundStyle(.secondary)
                    } else {
                        ForEach(report.sites) { site in
                            SiteRow(site: site) { pendingRemoval = site }
                        }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            } header: {
                HStack {
                    Text("Website Data")
                    Spacer()
                    if let report {
                        Text("\(report.sites.count) sites · \(report.cookies) cookies").foregroundStyle(.secondary)
                    }
                    Button {
                        Task { await loadReport() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh")
                }
            }

            Section {
                if workspace.session(for: profile) == nil {
                    Text("Open this profile to record its connections.").foregroundStyle(.secondary)
                } else if hosts.isEmpty {
                    Text("No connections yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(hosts.prefix(Self.hostLimit)) { HostRow(host: $0) }
                }
            } header: {
                Text("Connections")
            } footer: {
                Text("Hosts this profile connected to since it opened, measured by its local proxy. Traffic stays encrypted; only host names and byte counts are seen.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task(id: profile) { await loadReport() }
        .task(id: profile) { await pollConnections() }
        .confirmationDialog(
            "Delete data stored by \(pendingRemoval?.name ?? "")?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            presenting: pendingRemoval
        ) { site in
            Button("Delete Website Data", role: .destructive) {
                Task { await remove(site) }
            }
        } message: { _ in
            Text("Removes its cookies, storage and cache from “\(profile)”. You may need to sign in again.")
        }
    }

    private func loadReport() async {
        guard let store = try? workspace.dataStore(for: profile) else { return }
        report = await PrivacyInspector.report(for: store)
    }

    private func remove(_ site: PrivacyReport.Site) async {
        guard let store = try? workspace.dataStore(for: profile) else { return }
        await PrivacyInspector.remove(site: site.name, from: store)
        await loadReport()
    }

    private func pollConnections() async {
        while !Task.isCancelled {
            hosts = workspace.session(for: profile)?.proxy.log.hosts ?? []
            try? await Task.sleep(for: .seconds(2))
        }
    }
}

private struct SiteRow: View {
    let site: PrivacyReport.Site
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            SiteIcon(url: URL(string: "https://\(site.name)"), size: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(site.name)
                Text(site.dataTypes.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if site.cookies > 0 {
                Text("\(site.cookies) cookie\(site.cookies == 1 ? "" : "s")").foregroundStyle(.secondary).monospacedDigit()
            }
            Button(action: remove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete this site's data")
        }
    }
}

private struct HostRow: View {
    let host: HostSummary

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(host.host).lineLimit(1).truncationMode(.middle)
                Text(detail).font(.caption).foregroundStyle(host.blocked > 0 ? .red : .secondary)
            }
            Spacer()
            Text("↑ \(bytes(host.bytesUp))  ↓ \(bytes(host.bytesDown))").foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private var detail: String {
        var parts = ["\(host.connections) connection\(host.connections == 1 ? "" : "s")"]
        if host.blocked > 0 { parts.append("\(host.blocked) blocked") }
        if host.failed > 0 { parts.append("\(host.failed) failed") }
        return parts.joined(separator: " · ")
    }

    private func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}
