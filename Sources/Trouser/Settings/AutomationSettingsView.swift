import AppKit
import SwiftUI

struct AutomationSettingsView: View {
    let policy: Policy

    var body: some View {
        Form {
            Section {
                ForEach(ActionKind.allCases) { kind in
                    Picker(selection: Binding(
                        get: { policy.mode(for: kind) },
                        set: { policy.setMode($0, for: kind) }
                    )) {
                        ForEach(Mode.allCases) { Text($0.title).tag($0) }
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(kind.title)
                                Text(kind.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: kind.symbol)
                        }
                    }
                }
            } header: {
                Text("Automation Permissions")
            } footer: {
                Text("Ask shows an approval card over the page before the command runs. Site rules in Profiles › Rules override these per host. Pause in the Automation inspector blocks everything.")
                    .foregroundStyle(.secondary)
            }

            Section("Developer") {
                Toggle(isOn: Binding(
                    get: { policy.allowsWebInspector },
                    set: { policy.allowsWebInspector = $0 }
                )) {
                    Text("Allow Web Inspector")
                    Text("Lets Safari's Develop menu inspect and run scripts in pages. Applies to new tabs.")
                }
            }

            Section("Privacy") {
                LabeledContent {
                    Button("Burn Everything…", role: .destructive) {
                        NSApp.sendAction(#selector(AppDelegate.burnEverything(_:)), to: nil, from: nil)
                    }
                } label: {
                    Text("Website data")
                    Text("Closes every tab and deletes cookies, logins, storage and history for all profiles.")
                }
            }
        }
        .formStyle(.grouped)
    }
}
