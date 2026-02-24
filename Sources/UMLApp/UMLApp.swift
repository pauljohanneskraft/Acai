import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct UMLApp: App {
    init() {
        #if os(macOS)
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        if let image = Bundle.module.image(forResource: "AppIcon") {
            app.applicationIconImage = image
        }
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            ProjectBrowserView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project") {
                    NotificationCenter.default.post(name: .createNewProject, object: nil)
                }.keyboardShortcut("n", modifiers: [.command])
            }
        }
    }
}

