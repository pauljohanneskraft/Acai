import XCTest

@MainActor
final class ProjectBrowserScreen {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    /// Not a `.buttons` query — the button's `.buttonStyle(.plain)` strips native AppKit button
    /// chrome on macOS, so it no longer exposes as `AXButton`/`XCUIElementType.button` there.
    var newProjectButton: XCUIElement { app.descendants(matching: .any)["sidebar.newProjectButton"] }
    var deleteProjectConfirmButton: XCUIElement { app.buttons["sidebar.project.delete.confirmButton"] }
    var deleteCodebaseConfirmButton: XCUIElement { app.buttons["sidebar.codebase.delete.confirmButton"] }

    /// Not necessarily a `.buttons` query — SwiftUI's `List(selection:)` row/`DisclosureGroup` label
    /// surfaces to the accessibility tree in a shape that varies by platform.
    func projectRow(id: String) -> XCUIElement {
        app.descendants(matching: .any)["sidebar.project.\(id)"]
    }

    func codebaseRow(id: String) -> XCUIElement {
        app.descendants(matching: .any)["sidebar.codebase.\(id)"]
    }

    /// For a codebase added at test runtime (e.g. cloned from GitHub), whose `id` is a fresh random
    /// UUID the test can't predict ahead of time — matches the row's visible name label instead.
    func codebaseRow(named name: String) -> XCUIElement {
        app.staticTexts[name].firstMatch
    }

    // MARK: - Quick Open

    /// Compact width only — regular width pins `quickOpenFieldProxy` atop the sidebar instead.
    var quickOpenButton: XCUIElement { app.buttons["sidebar.quickOpenButton"] }
    /// iPad's pinned search-field proxy atop the sidebar `List` — tapping it opens the same Quick
    /// Open sheet `quickOpenButton`/⌘K do.
    var quickOpenFieldProxy: XCUIElement { app.descendants(matching: .any)["sidebar.quickOpenField"] }

    /// Opens Quick Open through whichever entry point this platform and width actually has.
    func openQuickOpen(file: StaticString = #filePath, line: UInt = #line) {
        let searchField = QuickOpenScreen(app: app).searchField
        #if os(macOS)
        // macOS's only entry point is ⌘K (`QuickOpenCommands`) — neither affordance exists there.
        newProjectButton.waitOrFail("the project browser", file: file, line: line)
        app.typeKey("k", modifierFlags: .command)
        searchField.waitOrFail("the Quick Open search field", file: file, line: line)
        #else
        let deadline = Date().addingTimeInterval(.uiTransition)
        while Date() < deadline, !quickOpenButton.exists, !quickOpenFieldProxy.exists {
            Thread.sleep(forTimeInterval: 0.1)
        }
        let entryPoint = quickOpenButton.exists ? quickOpenButton : quickOpenFieldProxy
        entryPoint.tap("a Quick Open entry point", until: searchField, file: file, line: line)
        #endif
    }

    // MARK: - Settings

    var settingsButton: XCUIElement { app.buttons["sidebar.settingsButton"] }

    /// macOS reaches Settings via the real `Settings` scene (⌘,); iOS via the sidebar's gear button.
    func openSettings(file: StaticString = #filePath, line: UInt = #line) {
        let patField = GitHubAccountScreen(app: app).patField
        #if os(macOS)
        newProjectButton.waitOrFail("the project browser", file: file, line: line)
        app.typeKey(",", modifierFlags: .command)
        SettingsScreen(app: app).accountsPane.waitOrFail("the Settings window", file: file, line: line)
        #else
        settingsButton.tap("Settings", until: SettingsScreen(app: app).sheet, file: file, line: line)
        #endif
        patField.waitOrFail("the Settings accounts section", file: file, line: line)
    }

    func closeSettings(file: StaticString = #filePath, line: UInt = #line) {
        let settings = SettingsScreen(app: app)
        #if os(macOS)
        app.typeKey("w", modifierFlags: .command)
        settings.accountsPane.waitForDisappearanceOrFail("the Settings window", file: file, line: line)
        #else
        settings.doneButton.tapWhenReady("the Settings sheet's Done button", file: file, line: line)
        settings.sheet.waitForDisappearanceOrFail("the Settings sheet", file: file, line: line)
        #endif
    }

    // MARK: - Activity indicator

    var activityIndicatorButton: XCUIElement { app.descendants(matching: .any)["activity.indicatorButton"] }
    func activityRow(id: String) -> XCUIElement { app.descendants(matching: .any)["activity.row.\(id)"] }
    func activityCancelButton(id: String) -> XCUIElement { app.buttons["activity.cancelButton.\(id)"] }
    var activityEmptyState: XCUIElement { app.descendants(matching: .any)["activity.emptyState"] }
    var activityDoneButton: XCUIElement { app.buttons["activity.doneButton"] }
}
