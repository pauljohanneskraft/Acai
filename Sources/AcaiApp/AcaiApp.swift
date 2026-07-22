import SwiftUI

/// The app's shared root scene content. `AcaiApp` is a library, not an executable — each platform's
/// real `@main` entry point lives in the XcodeGen-generated Xcode project under `App/` (one file
/// per platform, owning that platform's Info.plist/entitlements/asset catalog) and just wraps this
/// scene. Only one type in the final linked binary may carry `@main`, so it can't live here.
public struct AcaiRootScene: Scene {
    public init() {}

    public var body: some Scene {
        WindowGroup {
            ProjectBrowserView()
                .modifier(DiagramThemeProvider())
        }
        .commands {
            DiagramThemeCommands()
            #if os(macOS)
            KeyboardShortcutCommands()
            #endif
        }
        #if os(macOS)
        WindowGroup(id: KeyboardShortcutCommands.windowID) {
            KeyboardShortcutsPanel()
        }
        #endif
    }
}
