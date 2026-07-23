import SwiftUI

@main
struct RouseClosedLidHelperApp: App {
    @StateObject private var serviceManager = HelperServiceManager()

    var body: some Scene {
        WindowGroup {
            ContentView(serviceManager: serviceManager)
        }
        .windowResizability(.contentSize)

        Settings {
            EmptyView()
        }
    }
}

