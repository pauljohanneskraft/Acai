import XCTest

@MainActor
final class QueryScreen {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    var list: XCUIElement { app.descendants(matching: .any)["query.list"] }
    var emptyState: XCUIElement { app.descendants(matching: .any)["query.emptyState"] }
    var notIndexedState: XCUIElement { app.descendants(matching: .any)["query.notIndexedState"] }
    var codebaseNotFoundState: XCUIElement { app.descendants(matching: .any)["query.codebaseNotFoundState"] }
    var clearFiltersButton: XCUIElement { app.buttons["query.clearFiltersButton"] }
    var indexNowButton: XCUIElement { app.buttons["query.indexNowButton"] }

    var memberKindPicker: XCUIElement { app.descendants(matching: .any)["query.memberFilter.kindPicker"] }
    var minParametersField: XCUIElement { app.textFields["query.memberFilter.minParametersField"] }
    var mutablePublicStateToggle: XCUIElement {
        app.descendants(matching: .any)["query.memberFilter.mutablePublicStateToggle"]
    }
    var overridesToggle: XCUIElement { app.descendants(matching: .any)["query.memberFilter.overridesToggle"] }

    /// `id` is a `TypeQuery.TypeRow.id` (the type's qualified name, e.g. `"Base"`).
    func row(id: String) -> XCUIElement {
        app.descendants(matching: .any)["query.row.\(id)"]
    }
}
