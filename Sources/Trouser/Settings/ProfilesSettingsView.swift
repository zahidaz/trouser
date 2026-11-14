import AppKit
import SwiftUI

struct ProfilesSettingsView: View {
    let workspace: Workspace
    @State private var selection: String? = Workspace.defaultProfile
    @State private var page = Page.settings

    private enum Page: String, CaseIterable, Identifiable {
        case settings = "Browsing"
        case rules = "Rules"
        case data = "Website Data"

        var id: Self { self }
    }

    var body: some View {
        HStack(spacing: 0) {
            List(workspace.profileNames, id: \.self, selection: $selection) { name in
                Label {
                    Text(name)
                } icon: {
                    Image(systemName: workspace.session(for: name) == nil ? "person.crop.circle" : "person.crop.circle.fill")
                }
                .contextMenu {
                    if name != Workspace.defaultProfile {
                        Button("Delete Profile “\(name)”…") { delete(name) }
                    }
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 2) {
                    Button(action: create) {
                        Image(systemName: "plus").frame(width: 20, height: 20)
                    }
                    .help("New profile")
                    Button {
                        selection.map(delete)
                    } label: {
                        Image(systemName: "minus").frame(width: 20, height: 20)
                    }
                    .disabled(selection == nil || selection == Workspace.defaultProfile)
                    .help("Delete the selected profile and all its data")
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
            .frame(width: 180)
            Divider()
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func create() {
        guard let name = ProfilePrompt.ask(existing: workspace.profileNames) else { return }
        Task {
            do {
                try await workspace.open(name)
                selection = name
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    private func open(_ name: String) {
        Task {
            do {
                try await workspace.open(name)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    private func header(_ name: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.title3.weight(.semibold))
                Text(workspace.session(for: name) == nil ? "Closed" : "Open")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(workspace.session(for: name) == nil ? "Open Window" : "Show Window") { open(name) }
            if name != Workspace.defaultProfile {
                Button("Delete…", role: .destructive) { delete(name) }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private func delete(_ name: String) {
        guard name != Workspace.defaultProfile, DeleteConfirmation.confirm(name) else { return }
        Task {
            do {
                try await workspace.deleteKeepingWindowOpen(name)
                selection = Workspace.defaultProfile
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let selection, let store = try? workspace.settings(for: selection) {
            VStack(spacing: 0) {
                header(selection)
                Picker("Page", selection: $page) {
                    ForEach(Page.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .padding(.top, 14)
                switch page {
                case .settings:
                    ProfileSettingsForm(store: store, ruleError: workspace.session(for: selection)?.contentRuleError)
                case .rules:
                    if let rules = try? workspace.rules(for: selection) {
                        ProfileRulesForm(store: rules, policy: workspace.policy)
                    }
                case .data:
                    PrivacyDashboardView(workspace: workspace, profile: selection)
                }
            }
            .id(selection)
        } else {
            ContentUnavailableView("No Profile Selected", systemImage: "person.crop.circle")
        }
    }
}
