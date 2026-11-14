import SwiftUI

struct StartView: View {
    let session: ProfileSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                if session.history.visits.isEmpty {
                    welcome
                } else {
                    section("Recently Visited", action: Button("Clear") { session.history.removeAll() }) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 112), spacing: 20)], spacing: 22) {
                            ForEach(session.history.visits.prefix(16)) { visit in
                                FavoriteTile(visit: visit) { session.selectedTab?.load(visit.url) }
                                    .contextMenu {
                                        Button("Remove from Recently Visited") { session.history.remove(visit.url) }
                                    }
                            }
                        }
                    }
                }
                section("Privacy") {
                    HStack(spacing: 12) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.title)
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Profile “\(session.name)”").font(.headline)
                            Text("Cookies, logins and storage stay inside this profile.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quinary, in: .rect(cornerRadius: 14, style: .continuous))
                }
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, 40)
            .padding(.vertical, 56)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var welcome: some View {
        VStack(spacing: 10) {
            Image(systemName: "safari")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Search or enter a website name above.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private func section<Content: View>(_ title: String, action: Button<Text>? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.title3.weight(.bold))
                Spacer()
                action.buttonStyle(.link)
            }
            content()
        }
    }
}

private struct FavoriteTile: View {
    let visit: HistoryStore.Visit
    let open: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: open) {
            VStack(spacing: 8) {
                SiteIcon(url: visit.url, size: 64)
                    .shadow(color: .black.opacity(isHovered ? 0.25 : 0.12), radius: isHovered ? 8 : 4, y: 2)
                    .scaleEffect(isHovered ? 1.05 : 1)
                Text(visit.title)
                    .font(.callout)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 34, alignment: .top)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering }
        }
        .help(visit.url.absoluteString)
    }
}
