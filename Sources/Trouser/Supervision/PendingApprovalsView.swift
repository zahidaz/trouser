import SwiftUI

struct PendingApprovalsView: View {
    let workspace: Workspace

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(workspace.openSessions, id: \.name) { session in
                if session.supervisor.pendingEntry != nil {
                    VStack(alignment: .trailing, spacing: 0) {
                        Label(session.name, systemImage: "person.crop.circle")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.regularMaterial, in: .capsule)
                            .padding(.trailing, 36)
                            .padding(.bottom, -20)
                        ApprovalCard(supervisor: session.supervisor)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
}
