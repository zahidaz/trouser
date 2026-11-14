import SwiftUI

struct Editing<Value>: Identifiable {
    let id = UUID()
    let original: Value?
}

struct ProfileRulesForm: View {
    let store: RuleStore
    let policy: Policy
    @State private var siteSheet: Editing<SiteRule>?
    @State private var pinSheet: Editing<CertificatePin>?

    var body: some View {
        Form {
            if let problem = store.loadError ?? store.saveError {
                problemSection(problem)
            }
            sitesSection
            PatternListSection(
                title: "Protected Actions",
                footer: "Clicks and key presses on a target whose label contains one of these always ask, even when rules allow them. Use * for any text and ? for one character, e.g. send*for review.",
                placeholder: "Label, e.g. delete or pay *",
                items: store.rules.protectedLabels.map(\.text),
                add: addProtectedLabel,
                remove: removeProtectedLabel
            ) {
                Button("Restore Defaults", action: restoreProtectedLabels)
            }
            PatternListSection(
                title: "Navigation Fence",
                footer: "When set, automation can only open these hosts, including popups and redirects. Your own navigation is never fenced. Leave empty to allow every host.",
                placeholder: "Host, e.g. *.example.com",
                items: store.rules.fence.map(\.text),
                add: addFenceHost,
                remove: removeFenceHost
            )
            pinsSection
        }
        .formStyle(.grouped)
        .sheet(item: $siteSheet) { editing in
            SiteRuleEditor(original: editing.original, policy: policy, save: saveSite)
        }
        .sheet(item: $pinSheet) { editing in
            PinEditor(original: editing.original, save: savePin)
        }
    }

    private func problemSection(_ problem: String) -> some View {
        Section {
            Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            Button("Reset Rules to Defaults", role: .destructive, action: store.reset)
        } footer: {
            Text("While the rules file can't be read, every automation action in this profile is blocked.")
                .foregroundStyle(.secondary)
        }
    }

    private var sitesSection: some View {
        Section {
            ForEach(store.rules.sites) { site in
                RuleRow(title: site.pattern.text, detail: site.summary) {
                    siteSheet = Editing(original: site)
                } remove: {
                    removeSite(site)
                }
            }
            Button("Add Site Rule…") { siteSheet = Editing(original: nil) }
        } header: {
            Text("Site Rules")
        } footer: {
            Text("Override the global modes, camera and microphone for hosts like shop.example.com or *.example.com. The most specific pattern that sets an action decides it. Camera and microphone are denied unless a rule allows them.")
                .foregroundStyle(.secondary)
        }
    }

    private var pinsSection: some View {
        Section {
            ForEach(store.rules.pins) { pin in
                RuleRow(title: pin.pattern.text, detail: pin.summary) {
                    pinSheet = Editing(original: pin)
                } remove: {
                    removePin(pin)
                }
            }
            Button("Add Certificate Pin…") { pinSheet = Editing(original: nil) }
        } header: {
            Text("Certificate Pins")
        } footer: {
            Text("Connections to a pinned host must pass normal trust evaluation and then match an allowed issuer name or SHA-256 public key fingerprint. Failures block the load.")
                .foregroundStyle(.secondary)
        }
    }

    private func saveSite(_ site: SiteRule, replacing original: SiteRule?) {
        store.update { $0.sites.upsert(site, replacing: original?.id) }
    }

    private func removeSite(_ site: SiteRule) {
        store.update { $0.sites.removeAll { $0.id == site.id } }
    }

    private func savePin(_ pin: CertificatePin, replacing original: CertificatePin?) {
        store.update { $0.pins.upsert(pin, replacing: original?.id) }
    }

    private func removePin(_ pin: CertificatePin) {
        store.update { $0.pins.removeAll { $0.id == pin.id } }
    }

    private func addProtectedLabel(_ text: String) -> Bool {
        guard let label = LabelPattern(text) else { return false }
        store.update { $0.protectedLabels.upsert(label, replacing: nil) }
        return true
    }

    private func removeProtectedLabel(_ text: String) {
        store.update { $0.protectedLabels.removeAll { $0.text == text } }
    }

    private func restoreProtectedLabels() {
        store.update { $0.protectedLabels = ProfileRules.defaultProtectedLabels }
    }

    private func addFenceHost(_ text: String) -> Bool {
        guard let host = HostPattern(text) else { return false }
        store.update { $0.fence.upsert(host, replacing: nil) }
        return true
    }

    private func removeFenceHost(_ text: String) {
        store.update { $0.fence.removeAll { $0.text == text } }
    }
}

private struct RuleRow: View {
    let title: String
    let detail: String
    let edit: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.monospaced())
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Button("Edit…", action: edit)
            Button(action: remove) {
                Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            .help("Remove")
        }
    }
}
