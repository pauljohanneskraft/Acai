import XCTest

@MainActor
final class CodebaseDetailScreen {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    var reindexButton: XCUIElement { app.buttons["codebaseDetail.reindexButton"] }
    var reindexLoadedIndicator: XCUIElement { app.descendants(matching: .any)["codebaseDetail.reindex.loaded"] }
    var refSwitchLoadedIndicator: XCUIElement { app.descendants(matching: .any)["codebaseDetail.refSwitch.loaded"] }
    var pullLoadedIndicator: XCUIElement { app.descendants(matching: .any)["codebaseDetail.pull.loaded"] }

    /// `type` is a `DiagramType.rawValue` (e.g. `"class"`, `"sequence"`, `"callGraph"`).
    func diagramButton(type: String) -> XCUIElement {
        app.buttons["codebaseDetail.diagramButton.\(type)"]
    }

    /// Shown instead of `reindexButton` for a GitHub-backed codebase.
    var refPicker: XCUIElement { app.descendants(matching: .any)["codebaseDetail.refPicker"] }
    var pullButton: XCUIElement { app.buttons["codebaseDetail.pullButton"] }

    @discardableResult
    func chooseRef(_ label: String, timeout: TimeInterval = 10) -> XCUIElement {
        refPicker.choose(label, in: app, timeout: timeout)
    }

    var deleteCodebaseButton: XCUIElement { app.buttons["codebaseDetail.deleteCodebaseButton"] }
    var deleteCodebaseConfirmButton: XCUIElement {
        app.buttons.matching(identifier: "codebaseDetail.codebase.delete.confirmButton").firstMatch
    }
}
