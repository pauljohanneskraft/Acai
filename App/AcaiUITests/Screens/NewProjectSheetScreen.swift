import XCTest

@MainActor
final class NewProjectSheetScreen {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    var titleField: XCUIElement { app.textFields["newProjectSheet.titleField"] }
    var subtitleField: XCUIElement { app.textFields["newProjectSheet.subtitleField"] }
    /// `.firstMatch`: a toolbar button's identifier resolves to more than one accessibility node
    /// (the wrapping bar-item container and the nested button both carry it).
    var cancelButton: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "newProjectSheet.cancelButton").firstMatch
    }
    var createButton: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "newProjectSheet.createButton").firstMatch
    }
}
