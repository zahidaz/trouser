import Observation
import SwiftUI

@MainActor
@Observable
final class PinDraft {
    var pattern: String
    var issuers: String
    var fingerprints: String

    init(_ pin: CertificatePin?) {
        pattern = pin?.pattern.text ?? ""
        issuers = pin?.issuers.joined(separator: "\n") ?? ""
        fingerprints = pin?.spkiSHA256.map(\.description).joined(separator: "\n") ?? ""
    }

    var pin: CertificatePin? {
        guard let host = HostPattern(pattern) else { return nil }
        let keys = Self.lines(fingerprints).map(SPKIFingerprint.init)
        guard keys.allSatisfy({ $0 != nil }) else { return nil }
        let pin = CertificatePin(pattern: host, issuers: Self.lines(issuers), spkiSHA256: keys.compactMap { $0 })
        return pin.isEmpty ? nil : pin
    }

    var problem: String? {
        if HostPattern(pattern) == nil { return "Enter a host pattern." }
        if let bad = Self.lines(fingerprints).first(where: { SPKIFingerprint($0) == nil }) {
            return "“\(bad)” is not a SHA-256 fingerprint in base64 or hex."
        }
        return pin == nil ? "Add at least one issuer name or fingerprint." : nil
    }

    private static func lines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

struct PinEditor: View {
    let original: CertificatePin?
    let save: (CertificatePin, CertificatePin?) -> Void
    @State private var draft: PinDraft
    @Environment(\.dismiss) private var dismiss

    init(original: CertificatePin?, save: @escaping (CertificatePin, CertificatePin?) -> Void) {
        self.original = original
        self.save = save
        _draft = State(initialValue: PinDraft(original))
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Host pattern", text: $draft.pattern, prompt: Text("shop.example.com or *.example.com"))
                }
                Section {
                    TextEditor(text: $draft.issuers)
                        .font(.body.monospaced())
                        .frame(height: 70)
                } header: {
                    Text("Allowed issuers")
                } footer: {
                    Text("One per line. Matches the organization or common name of the server certificate's issuer, e.g. Example Trust Services.")
                        .foregroundStyle(.secondary)
                }
                Section {
                    TextEditor(text: $draft.fingerprints)
                        .font(.body.monospaced())
                        .frame(height: 90)
                } header: {
                    Text("Allowed SHA-256 SPKI fingerprints")
                } footer: {
                    Text("One per line, base64 (optionally prefixed sha256/) or hex. Matches any certificate in the chain.")
                        .foregroundStyle(.secondary)
                }
                if let problem = draft.problem {
                    Text(problem).font(.caption).foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.pin == nil)
            }
            .padding(16)
        }
        .frame(width: 520, height: 520)
    }

    private func cancel() {
        dismiss()
    }

    private func commit() {
        guard let pin = draft.pin else { return }
        save(pin, original)
        dismiss()
    }
}
