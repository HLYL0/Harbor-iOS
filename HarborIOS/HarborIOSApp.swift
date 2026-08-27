import SwiftUI

@main
struct HarborIOSApp: App {
    @StateObject private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                .preferredColorScheme(.dark)
                .task { await environment.start() }
        }
    }
}
