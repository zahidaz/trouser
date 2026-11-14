import SwiftUI

@MainActor
@Observable
final class SettingsRoute {
    enum Tab: Hashable {
        case automation, profiles
    }

    var tab = Tab.automation
}

struct SettingsView: View {
    let workspace: Workspace
    @Bindable var route: SettingsRoute

    var body: some View {
        TabView(selection: $route.tab) {
            AutomationSettingsView(policy: workspace.policy)
                .tabItem { Label("Automation", systemImage: "slider.horizontal.3") }
                .tag(SettingsRoute.Tab.automation)
            ProfilesSettingsView(workspace: workspace)
                .tabItem { Label("Profiles", systemImage: "person.2.crop.square.stack") }
                .tag(SettingsRoute.Tab.profiles)
        }
        .frame(width: 860, height: 680)
    }
}
