import SwiftUI

struct ProfileSettingsForm: View {
    @Bindable var store: ProfileSettingsStore
    let ruleError: String?

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $store.settings.javaScript) {
                    Text("JavaScript")
                    Text("Turn off to load pages without running their scripts.")
                }
                Toggle(isOn: $store.settings.lockdownMode) {
                    Text("Lockdown Mode")
                    Text("Disables complex web technologies such as JIT, WebGL and some fonts, as in macOS Lockdown Mode.")
                }
                Picker("Content mode", selection: $store.settings.contentMode) {
                    Text("Recommended").tag(ProfileSettings.ContentMode.recommended)
                    Text("Desktop").tag(ProfileSettings.ContentMode.desktop)
                    Text("Mobile").tag(ProfileSettings.ContentMode.mobile)
                }
                TextField("User agent", text: $store.settings.userAgent, prompt: Text("Safari (default)"))
                LabeledContent("Page zoom") {
                    Stepper(value: $store.settings.pageZoom, in: ProfileSettings.zoomRange, step: 0.1) {
                        Text(store.settings.pageZoom, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                    }
                }
                Picker(selection: $store.settings.inactiveScheduling) {
                    Text("Suspend").tag(ProfileSettings.InactiveScheduling.suspend)
                    Text("Throttle").tag(ProfileSettings.InactiveScheduling.throttle)
                    Text("Keep running").tag(ProfileSettings.InactiveScheduling.none)
                } label: {
                    Text("Background tabs")
                    Text("Applies to new tabs.")
                }
            } header: {
                Text("Pages")
            } footer: {
                Text("JavaScript, Lockdown Mode and content mode take effect on the next page load.")
                    .foregroundStyle(.secondary)
            }

            Section("Viewport") {
                Toggle(isOn: fixedViewport) {
                    Text("Fixed viewport size")
                    Text("Pages render at this size whatever the window size, so screenshots and coordinates stay stable.")
                }
                if let viewport = store.settings.viewport {
                    LabeledContent("Size") {
                        HStack(spacing: 6) {
                            dimensionField(viewport.width) { store.settings.viewport?.width = $0 }
                            Text("×")
                            dimensionField(viewport.height) { store.settings.viewport?.height = $0 }
                        }
                    }
                }
            }

            Section {
                Toggle(isOn: $store.settings.preciseMode) {
                    Text("Precise mode")
                    Text("Gives automation a live, exact view of pages: roles, labels, typed values, checkbox states and exact positions, read by a WebKit extension inside the page process. This profile's pages then run in a WebKit process with reduced hardening, so leave it off for profiles you browse untrusted sites with.")
                }
                Toggle(isOn: $store.settings.liveScreenshot) {
                    Text("Live screenshot")
                    Text("Keeps a low-quality image of the current page in memory, refreshed within a second of a change, so automation can see the page in one step. Reading it is a view action: your Allow, Ask and Block modes, site rules and Pause apply, and sites where viewing is blocked are never captured. Each read is saved for your user only and replaced by the next one.")
                }
            } header: {
                Text("Automation")
            } footer: {
                Text("Applies to tabs opened afterwards. If the extension can't load, the profile keeps browsing with the standard page model.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Block images", isOn: $store.settings.blockImages)
                Toggle("Block web fonts", isOn: $store.settings.blockFonts)
                Toggle(isOn: $store.settings.blockTrackers) {
                    Text("Block trackers")
                    Text("Third-party requests to \(TrackerList.domains.count) common ad and analytics domains.")
                }
            } header: {
                Text("Content Blocking")
            } footer: {
                if let ruleError {
                    Text("Content rules failed to compile: \(ruleError)").foregroundStyle(.red)
                }
            }

            StringListEditor(
                title: "Blocked Domains",
                detail: "Requests to these domains and their subdomains are never made.",
                prompt: "ads.example.com",
                values: $store.settings.blockedDomains,
                normalize: ContentRules.normalizedDomain
            )
            StringListEditor(
                title: "Hidden Elements",
                detail: "CSS selectors hidden on every page.",
                prompt: ".cookie-banner",
                values: $store.settings.hiddenSelectors,
                normalize: Self.trimmed
            )
            StringListEditor(
                title: "Allowed Hosts",
                detail: "When set, connections to any other host are refused. Subdomains match; *.example.com matches only subdomains.",
                prompt: "example.com",
                values: $store.settings.allowedHosts,
                normalize: Self.host
            )
            StringListEditor(
                title: "Blocked Hosts",
                detail: "Connections to these hosts are refused by the profile's proxy, even when allowed above.",
                prompt: "tracker.example",
                values: $store.settings.blockedHosts,
                normalize: Self.host
            )
        }
        .formStyle(.grouped)
    }

    private var fixedViewport: Binding<Bool> {
        Binding(
            get: { store.settings.viewport != nil },
            set: { store.settings.viewport = $0 ? .standard : nil }
        )
    }

    private func dimensionField(_ value: Int, set: @escaping (Int) -> Void) -> some View {
        TextField("", value: Binding(get: { value }, set: { newValue in
            let range = ProfileSettings.Viewport.range
            set(min(max(newValue, range.lowerBound), range.upperBound))
        }), format: .number.grouping(.never))
        .labelsHidden()
        .multilineTextAlignment(.trailing)
        .frame(width: 64)
    }

    private static func trimmed(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func host(_ text: String) -> String? {
        let value = HostRules.normalize(text)
        return value.isEmpty || value.contains(where: { $0.isWhitespace || $0 == "/" }) ? nil : value
    }
}
