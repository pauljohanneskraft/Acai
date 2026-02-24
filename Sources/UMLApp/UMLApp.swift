import SwiftUI
import UMLLibrary

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
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        VStack {
            Text("Hello from the Package App!")
        }
        .padding()
    }
}
