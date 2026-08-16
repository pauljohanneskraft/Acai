import CoreSpotlight
import SwiftUI

/// The app's shared root scene content. `AcaiApp` is a library, not an executable — each platform's
/// real `@main` entry point lives in the XcodeGen-generated Xcode project under `App/` (one file
/// per platform, owning that platform's Info.plist/entitlements/asset catalog) and just wraps this
/// scene. Only one type in the final linked binary may carry `@main`, so it can't live here.
public struct AcaiRootScene: Scene {
    // Shared across scenes (the main `WindowGroup` and macOS's `Settings` scene, which is a
    // *separate* `Scene` a view-owned `@StateObject` on `ProjectBrowserView` can't reach) — see
    // each type's own doc comment for why it has to live here rather than lower in the hierarchy.
    @StateObject private var accountStore = GitHubAccountStore()
    @StateObject private var quickOpenPresenter = QuickOpenPresenter()
    @StateObject private var settingsPresenter = SettingsPresenter()
    @StateObject private var handoffPresenter = HandoffContinuationPresenter()

    public init() {}

    public var body: some Scene {
        WindowGroup {
            ProjectBrowserView()
                .modifier(DiagramThemeProvider())
                .preferredColorScheme(UITestFixtureResolver().resolveColorScheme())
                .onContinueUserActivity(DiagramHandoffActivity.activityType) { activity in
                    guard let raw = activity.userInfo?["generatedDiagramID"] as? String, let id = UUID(uuidString: raw)
                    else { return }
                    handoffPresenter.pendingTarget = .diagram(id)
                }
                .onContinueUserActivity(CodebaseHandoffActivity.activityType) { activity in
                    guard let raw = activity.userInfo?["codebaseID"] as? String, let id = UUID(uuidString: raw)
                    else { return }
                    handoffPresenter.pendingTarget = .codebase(id)
                }
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else {
                        return
                    }
                    handoffPresenter.pendingTarget = .spotlightItem(identifier)
                }
        }
        .commands {
            DiagramThemeCommands()
            #if os(macOS)
            KeyboardShortcutCommands()
            QuickOpenCommands()
            #endif
        }
        // Scene-level (not just on the `WindowGroup`'s content view) so `.commands` above — which
        // renders into the menu bar, a separate view hierarchy from the window's content — can also
        // read these via `@EnvironmentObject` (`QuickOpenCommands` needs `quickOpenPresenter`).
        .environmentObject(accountStore)
        .environmentObject(quickOpenPresenter)
        .environmentObject(settingsPresenter)
        .environmentObject(handoffPresenter)
        #if os(macOS)
        WindowGroup(id: KeyboardShortcutCommands.windowID) {
            KeyboardShortcutsPanel()
        }
        // The real `Settings` scene (⌘,) — `accountStore` is the same instance the main window's
        // `NewCodebaseSheet` reads, so signing in/out here is reflected there immediately.
        Settings {
            SettingsView()
                .environmentObject(accountStore)
        }
        #endif
    }
}
