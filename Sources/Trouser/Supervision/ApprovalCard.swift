import SwiftUI

struct ApprovalCard: View {
    let supervisor: Supervisor

    var body: some View {
        if let entry = supervisor.pendingEntry {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: entry.kind.symbol)
                        .font(.title2)
                        .foregroundStyle(.orange)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        if entry.protection != nil {
                            ProtectedBadge()
                        }
                        Text("Automation wants to \(entry.kind.verb)").font(.headline)
                        Text(entry.summary)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .textSelection(.enabled)
                        if let protection = entry.protection, let label = entry.context.label {
                            Text("Target “\(label)” matches the protected action “\(protection.text)”.")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.red)
                                .lineLimit(3)
                        }
                        if let host = entry.context.host {
                            Text("on \(host)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                HStack(spacing: 10) {
                    Spacer()
                    Button("Deny") { supervisor.resolve(false) }
                    Button("Allow") { supervisor.resolve(true) }
                        .buttonStyle(.borderedProminent)
                }
                .controlSize(.large)
            }
            .padding(18)
            .frame(width: 440)
            .background(.regularMaterial, in: .rect(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.separator))
            .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
            .padding(28)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

private struct ProtectedBadge: View {
    var body: some View {
        Label("Protected", systemImage: "lock.shield.fill")
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.red, in: .capsule)
            .padding(.bottom, 2)
    }
}
