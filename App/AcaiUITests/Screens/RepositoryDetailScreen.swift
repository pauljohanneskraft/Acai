import XCTest

@MainActor
final class RepositoryDetailScreen {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    var fetchNowButton: XCUIElement { app.buttons["repository.fetchNowButton"] }
    var removeButton: XCUIElement { app.buttons["repository.removeButton"] }

    /// `.firstMatch`: this identifier can resolve to more than one accessibility node for a
    /// system-styled `.confirmationDialog` action, matching `ProjectDetailScreen`'s equivalent.
    var removeConfirmButton: XCUIElement {
        app.buttons.matching(identifier: "repository.remove.confirmButton").firstMatch
    }

    var diskSizeValue: XCUIElement { app.descendants(matching: .any)["repository.diskSizeValue"] }
    var lastFetchedValue: XCUIElement { app.descendants(matching: .any)["repository.lastFetchedValue"] }

    /// Matches the `Section` header's literal text — the header has no accessibility identifier of
    /// its own, since `Section(.app(...))`'s string-based initializer offers no view to attach one to.
    func codebasesSectionHeader(count: Int) -> XCUIElement {
        app.staticTexts["Codebases (\(count))"]
    }

    /// The `.alert` shown when removal is blocked by a still-referencing codebase — presented as
    /// `app.sheets` on macOS and `app.alerts` on iOS/iPadOS, matching every other alert in this suite.
    var blockedAlert: XCUIElement {
        #if os(macOS)
        return app.sheets.firstMatch
        #else
        return app.alerts.firstMatch
        #endif
    }

    var blockedAlertOKButton: XCUIElement { blockedAlert.buttons["OK"] }
}
