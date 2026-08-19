import AppKit
import SwiftUI
import AcaiApp

@main
struct AcaiMacApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        AcaiRootScene()
    }
}

/// Activation alone doesn't order any window front, and none exists yet at launch, so retrying
/// until one appears closes the same gap a Dock-icon click otherwise would.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        orderFirstWindowFrontWhenReady()
    }

    private func orderFirstWindowFrontWhenReady() {
        guard let window = NSApplication.shared.windows.first else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.orderFirstWindowFrontWhenReady()
            }
            return
        }
        window.makeKeyAndOrderFront(nil)
    }
}
