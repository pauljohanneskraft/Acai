import AppIntents
import SwiftUI
import AcaiApp

@main
struct AcaiiOSApp: App {
    var body: some Scene {
        AcaiRootScene()
    }
}

/// Pulls `AcaiApp`'s intents into this app's App Intents metadata.
struct AcaiiOSAppIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [AcaiAppIntentsPackage.self] }
}
