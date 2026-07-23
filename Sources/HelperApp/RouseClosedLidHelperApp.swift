import Darwin
import SwiftUI

@main
struct RouseClosedLidHelperApp: App {
    @StateObject private var serviceManager = HelperServiceManager()

    init() {
        if CommandLine.arguments.dropFirst() == ["--self-test"] {
            print("Rouse Closed-Lid Helper self-test passed")
            exit(EXIT_SUCCESS)
        }
    }

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
