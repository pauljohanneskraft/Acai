import XCTest

/// Accessors for the Projects sidebar (`ProjectBrowserView`) — the root screen every journey
/// starts from. See `TESTING_ARCHITECTURE.md` Layer 2.
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

    /// A project's sidebar row. Not necessarily a `.buttons` query — SwiftUI's `List(selection:)`
    /// row/`DisclosureGroup` label surfaces to the accessibility tree in a shape that varies by
    /// platform, so this matches any element kind carrying the identifier.
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
}
