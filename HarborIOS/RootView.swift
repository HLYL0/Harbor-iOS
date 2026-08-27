import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(HarborTheme.accent)
        .toolbarBackground(HarborTheme.raised, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}
