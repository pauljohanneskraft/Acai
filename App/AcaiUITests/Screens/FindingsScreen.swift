import XCTest

/// Accessors for the project-level Findings view (`FindingsView`) — its loading/empty states,
/// filters, and rows, plus each row's "Open in…"/"View Source"/"Suppress" actions.
@MainActor
final class FindingsScreen {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    var list: XCUIElement { app.descendants(matching: .any)["findings.list"] }
    var loadingState: XCUIElement { app.descendants(matching: .any)["findings.loadingState"] }
    var emptyState: XCUIElement { app.descendants(matching: .any)["findings.emptyState"] }
    var noCodebasesState: XCUIElement { app.descendants(matching: .any)["findings.noCodebasesState"] }
    var notIndexedState: XCUIElement { app.descendants(matching: .any)["findings.notIndexedState"] }

    var codebaseFilter: XCUIElement { app.descendants(matching: .any)["findings.codebaseFilter"] }
    /// Not a `.buttons` query — `.toggleStyle(.button)` still renders as a native `Switch` in this
    /// accessibility tree (checked via a live UI-test run, not assumed), same reasoning as
    /// `ProjectBrowserScreen.newProjectButton`'s own `.descendants(matching: .any)` comment.
    var showSuppressedToggle: XCUIElement { app.descendants(matching: .any)["findings.showSuppressedToggle"] }

    /// `kind` is a `Finding.Kind.rawValue` (`"violation"`, `"deadCode"`, `"health"`).
    func kindFilter(_ kind: String) -> XCUIElement {
        app.buttons["findings.kindFilter.\(kind)"]
    }

    /// `id` is the finding's own stable `Finding.id`.
    func row(id: String) -> XCUIElement {
        app.descendants(matching: .any)["findings.row.\(id)"]
    }

    var suppressButton: XCUIElement { app.buttons["findings.row.suppressButton"].firstMatch }
    var unsuppressButton: XCUIElement { app.buttons["findings.row.unsuppressButton"].firstMatch }
}
