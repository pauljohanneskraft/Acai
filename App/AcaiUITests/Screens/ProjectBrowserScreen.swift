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
    var deleteCodebaseConfirmButton: XCUIElement {
        app.buttons.matching(identifier: "sidebar.codebase.delete.confirmButton").firstMatch
    }

    /// Not necessarily a `.buttons` query — SwiftUI's `List(selection:)` row/`DisclosureGroup` label
    /// surfaces to the accessibility tree in a shape that varies by platform.
    func projectRow(id: String) -> XCUIElement {
        app.descendants(matching: .any)["sidebar.project.\(id)"]
    }

    func codebaseRow(id: String) -> XCUIElement {
        app.descendants(matching: .any)["sidebar.codebase.\(id)"]
    }

    /// A predicate rather than a subscript: identifier subscripts are capped at 128 characters, which a
    /// fixture's `file://` remote URL exceeds. The row's icon carries the identifier too, and an icon
    /// never reports as hittable, so this matches the row's label — what a codebase row is tapped by.
    func repositoryRow(remoteURL: String) -> XCUIElement {
        app.staticTexts.matching(
            NSPredicate(format: "identifier == %@", "sidebar.repository.\(remoteURL)")
        ).firstMatch
    }

    /// Scoped to the sidebar's own rows — a detail screen may list a codebase under the same name.
    func sidebarCodebaseRow(named name: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH 'sidebar.codebase.' AND (label == %@ OR value == %@ OR title == %@)",
            name, name, name
        )).firstMatch
    }

    /// Only exists on compact width, where a pushed detail screen covers the sidebar.
    var backButton: XCUIElement { app.buttons["BackButton"] }

    /// Deletes through the row's own affordance: a context menu on macOS and iPad, a swipe action on
    /// iPhone's compact width.
    func deleteCodebase(_ row: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        row.waitUntilReady("the codebase's sidebar row", file: file, line: line)
        SystemBanners().dismiss(file: file, line: line)
        #if os(macOS)
        row.rightClick()
        // Window-scoped: the system Edit menu's own "Delete" item also matches an unscoped query.
        let delete = app.windows.firstMatch.descendants(matching: .any)["Delete"]
        #else
        let delete = app.buttons["Delete"]
        if SnapshotPlatform().usesCompactLayout {
            row.swipeLeft()
        } else {
            row.press(forDuration: 1.5)
        }
        #endif
        delete.tapWhenReady("the row's Delete action", file: file, line: line)
        deleteCodebaseConfirmButton.tapWhenReady("the codebase delete confirmation", file: file, line: line)
        row.waitForDisappearanceOrFail("the deleted codebase's sidebar row", file: file, line: line)
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

    /// ⌘K, from a hardware keyboard on iPad.
    func openQuickOpenWithKeyboard(file: StaticString = #filePath, line: UInt = #line) {
        newProjectButton.waitOrFail("the project browser", file: file, line: line)
        app.typeKey("k", modifierFlags: .command)
        QuickOpenScreen(app: app).searchField.waitOrFail("the Quick Open search field", file: file, line: line)
    }

    /// Opens Quick Open through whichever entry point this platform and width actually has.
    func openQuickOpen(file: StaticString = #filePath, line: UInt = #line) {
        #if os(macOS)
        // macOS's only entry point is ⌘K (`QuickOpenCommands`) — neither affordance exists there.
        openQuickOpenWithKeyboard(file: file, line: line)
        #else
        let entryPoint = SnapshotPlatform().usesCompactLayout ? quickOpenButton : quickOpenFieldProxy
        entryPoint.tap("the Quick Open entry point", until: QuickOpenScreen(app: app).searchField, file: file, line: line)
        #endif
    }

    /// ⇧⌘/, from the Mac's menu bar or an iPad's hardware keyboard.
    func openKeyboardShortcutsWithKeyboard(file: StaticString = #filePath, line: UInt = #line) {
        newProjectButton.waitOrFail("the project browser", file: file, line: line)
        app.typeKey("/", modifierFlags: [.command, .shift])
        KeyboardShortcutsScreen(app: app).panel.waitOrFail("the Keyboard Shortcuts panel", file: file, line: line)
    }

    // MARK: - Settings

    var settingsButton: XCUIElement { app.buttons["sidebar.settingsButton"] }

    /// ⌘, — the `Settings` scene on macOS, `SettingsCommands` on iPad.
    func openSettingsWithKeyboard(file: StaticString = #filePath, line: UInt = #line) {
        newProjectButton.waitOrFail("the project browser", file: file, line: line)
        app.typeKey(",", modifierFlags: .command)
        #if os(macOS)
        SettingsScreen(app: app).accountsPane.waitOrFail("the Settings window", file: file, line: line)
        #else
        SettingsScreen(app: app).sheet.waitOrFail("the Settings sheet", file: file, line: line)
        #endif
    }

    /// macOS reaches Settings via the real `Settings` scene (⌘,); iOS via the sidebar's gear button.
    func openSettings(file: StaticString = #filePath, line: UInt = #line) {
        let patField = GitHubAccountScreen(app: app).patField
        #if os(macOS)
        openSettingsWithKeyboard(file: file, line: line)
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
