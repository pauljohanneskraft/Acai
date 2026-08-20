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
    /// See `ProjectDetailScreen.codebaseRow(named:)`'s identical reasoning.
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
        #if os(macOS)
        // macOS's only entry point is ⌘K (`QuickOpenCommands`) — neither affordance exists there.
        app.typeKey("k", modifierFlags: .command)
        #else
        if quickOpenButton.waitForExistence(timeout: 5) {
            quickOpenButton.tap()
        } else {
            quickOpenFieldProxy.waitOrFail("a Quick Open entry point", file: file, line: line)
            quickOpenFieldProxy.tap()
        }
        #endif
    }

    // MARK: - Settings

    var settingsButton: XCUIElement { app.buttons["sidebar.settingsButton"] }

    // MARK: - Activity indicator

    var activityIndicatorButton: XCUIElement { app.descendants(matching: .any)["activity.indicatorButton"] }
    func activityRow(id: String) -> XCUIElement { app.descendants(matching: .any)["activity.row.\(id)"] }
    func activityCancelButton(id: String) -> XCUIElement { app.buttons["activity.cancelButton.\(id)"] }
    var activityEmptyState: XCUIElement { app.descendants(matching: .any)["activity.emptyState"] }
    var activityDoneButton: XCUIElement { app.buttons["activity.doneButton"] }
}
