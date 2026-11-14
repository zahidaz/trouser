import Observation
import SwiftUI

@MainActor
@Observable
final class SiteRuleDraft {
    var pattern: String
    private var actions: [ActionKind: Mode]
    private var media: [MediaDevice: MediaMode]

    init(_ rule: SiteRule?) {
        pattern = rule?.pattern.text ?? ""
        actions = rule?.actions ?? [:]
        media = rule?.media ?? [:]
    }

    var rule: SiteRule? {
        HostPattern(pattern).map { SiteRule(pattern: $0, actions: actions, media: media) }
    }

    func mode(for kind: ActionKind) -> Mode? {
        actions[kind]
    }

    func setMode(_ mode: Mode?, for kind: ActionKind) {
        actions[kind] = mode
    }

    func mediaMode(for device: MediaDevice) -> MediaMode? {
        media[device]
    }

    func setMediaMode(_ mode: MediaMode?, for device: MediaDevice) {
        media[device] = mode
    }
}

struct SiteRuleEditor: View {
    let original: SiteRule?
    let policy: Policy
    let save: (SiteRule, SiteRule?) -> Void
    @State private var draft: SiteRuleDraft
    @Environment(\.dismiss) private var dismiss

    init(original: SiteRule?, policy: Policy, save: @escaping (SiteRule, SiteRule?) -> Void) {
        self.original = original
        self.policy = policy
        self.save = save
        _draft = State(initialValue: SiteRuleDraft(original))
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Host pattern", text: $draft.pattern, prompt: Text("shop.example.com or *.example.com"))
                } footer: {
                    Text("*.example.com matches example.com and every subdomain.").foregroundStyle(.secondary)
                }
                Section("Automation") {
                    ForEach(ActionKind.allCases) { kind in
                        Picker(selection: modeBinding(kind)) {
                            Text("Global (\(policy.mode(for: kind).title))").tag(Mode?.none)
                            ForEach(Mode.allCases) { Text($0.title).tag(Mode?.some($0)) }
                        } label: {
                            Label(kind.title, systemImage: kind.symbol)
                        }
                    }
                }
                Section {
                    ForEach(MediaDevice.allCases) { device in
                        Picker(selection: mediaBinding(device)) {
                            Text("Default (Deny)").tag(MediaMode?.none)
                            ForEach(MediaMode.allCases) { Text($0.title).tag(MediaMode?.some($0)) }
                        } label: {
                            Label(device.title, systemImage: device.symbol)
                        }
                    }
                } header: {
                    Text("Media")
                } footer: {
                    Text("Ask shows a prompt to you over the page. Automation can't answer it.").foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.rule == nil)
            }
            .padding(16)
        }
        .frame(width: 460, height: 600)
    }

    private func modeBinding(_ kind: ActionKind) -> Binding<Mode?> {
        Binding(get: { draft.mode(for: kind) }, set: { draft.setMode($0, for: kind) })
    }

    private func mediaBinding(_ device: MediaDevice) -> Binding<MediaMode?> {
        Binding(get: { draft.mediaMode(for: device) }, set: { draft.setMediaMode($0, for: device) })
    }

    private func cancel() {
        dismiss()
    }

    private func commit() {
        guard let rule = draft.rule else { return }
        save(rule, original)
        dismiss()
    }
}
