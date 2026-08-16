import XCTest

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
    /// accessibility tree (confirmed via a live UI-test run).
    var showSuppressedToggle: XCUIElement { app.descendants(matching: .any)["findings.showSuppressedToggle"] }
    var suppressionSaveLoadedIndicator: XCUIElement {
        app.descendants(matching: .any)["findings.suppressionSave.loaded"]
    }

    /// `kind` is a `Finding.Kind.rawValue` (`"violation"`, `"deadCode"`, `"health"`).
    func kindFilter(_ kind: String) -> XCUIElement {
        app.buttons["findings.kindFilter.\(kind)"]
    }

    func row(id: String) -> XCUIElement {
        app.descendants(matching: .any)["findings.row.\(id)"]
    }

    /// Every row's Suppress/Un-suppress button shares the SAME identifier
    /// (`findings.row.suppressButton`), so a bare `.firstMatch` query against it re-resolves fresh on
    /// every access — if the list reflows between a `waitForExistence` and the following `.tap()`,
    /// those two accesses can silently resolve to two different rows. Scoping to one captured row
    /// element up front removes that ambiguity.
    var firstViolationRow: XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'findings.row.violation-'"))
            .firstMatch
    }

    func suppressButton(in row: XCUIElement) -> XCUIElement { row.buttons["findings.row.suppressButton"] }
    func unsuppressButton(in row: XCUIElement) -> XCUIElement { row.buttons["findings.row.unsuppressButton"] }
}
