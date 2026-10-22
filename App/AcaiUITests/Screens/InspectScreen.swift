import XCTest

@MainActor
final class InspectScreen {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    var list: XCUIElement { app.descendants(matching: .any)["inspect.list"] }
    var emptyState: XCUIElement { app.descendants(matching: .any)["inspect.emptyState"] }
    var notIndexedState: XCUIElement { app.descendants(matching: .any)["inspect.notIndexedState"] }
    var codebaseNotFoundState: XCUIElement { app.descendants(matching: .any)["inspect.codebaseNotFoundState"] }
    /// Opens the filter sheet — every filter control lives there, not inline.
    var filterButton: XCUIElement { app.buttons["inspect.filterButton"] }
    var filterSheetDoneButton: XCUIElement { app.buttons["inspect.filterSheetDoneButton"] }
    var clearFiltersButton: XCUIElement { app.buttons["inspect.clearFiltersButton"] }
    var indexNowButton: XCUIElement { app.buttons["inspect.indexNowButton"] }

    var memberKindPicker: XCUIElement { app.descendants(matching: .any)["inspect.memberFilter.kindPicker"] }
    var minParametersField: XCUIElement { app.textFields["inspect.memberFilter.minParametersField"] }
    var mutablePublicStateToggle: XCUIElement {
        app.descendants(matching: .any)["inspect.memberFilter.mutablePublicStateToggle"]
    }
    var overridesToggle: XCUIElement { app.descendants(matching: .any)["inspect.memberFilter.overridesToggle"] }

    /// `id` is a `TypeQuery.TypeRow.id` (the type's qualified name, e.g. `"SampleSwiftPackage.Base"`).
    func row(id: String) -> XCUIElement {
        app.descendants(matching: .any)["inspect.row.\(id)"]
    }
}
