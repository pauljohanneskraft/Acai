import XCTest

final class StateDiagramScreen: DiagramScreenBase {
    /// Keyed by `StateDiagram.State.name` — no separate stable id, same caveat as
    /// `ClassDiagramScreen.typeNode`.
    func stateNode(named name: String) -> XCUIElement {
        app.descendants(matching: .any)["diagram.stateNode.\(name)"]
    }

    // MARK: - Config sheet (`StateConfigSheet`, the creation-time flow from `CodebaseDetailView`)

    var scopePicker: XCUIElement { app.descendants(matching: .any)["stateConfig.scopePicker"] }
    var variablePicker: XCUIElement { app.descendants(matching: .any)["stateConfig.variablePicker"] }
    /// `.firstMatch`: a toolbar button's identifier resolves to more than one accessibility node
    /// (the wrapping bar-item container and the nested button both carry it).
    var createButton: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "stateConfig.createButton").firstMatch
    }

    // MARK: - Settings tab (`StateDiagramSidebar` — call `openSettingsTab()` first)

    var settingsScopePicker: XCUIElement { app.descendants(matching: .any)["diagram.stateSettings.scopePicker"] }
    var settingsVariablePicker: XCUIElement { app.descendants(matching: .any)["diagram.stateSettings.variablePicker"] }
    var settingsApplyButton: XCUIElement { app.buttons["diagram.stateSettings.applyButton"] }
}
