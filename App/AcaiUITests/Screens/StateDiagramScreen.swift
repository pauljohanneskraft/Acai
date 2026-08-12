import XCTest

/// Adds State Diagram-specific accessors (canvas state nodes, the variable-selection config sheet,
/// and the Settings tab's live variable-selection form and Inspector tab) to
/// `DiagramScreenBase`'s shared toolbar/sidebar accessors.
final class StateDiagramScreen: DiagramScreenBase {
    /// A state box, by its `StateDiagram.State.name` — mirrors `ClassDiagramScreen.typeNode`, same
    /// "keyed by name, no stable id" caveat.
    func stateNode(named name: String) -> XCUIElement {
        app.descendants(matching: .any)["diagram.stateNode.\(name)"]
    }

    // MARK: - Config sheet (`StateConfigSheet`, the creation-time flow from `CodebaseDetailView`)

    var scopePicker: XCUIElement { app.descendants(matching: .any)["stateConfig.scopePicker"] }
    var variablePicker: XCUIElement { app.descendants(matching: .any)["stateConfig.variablePicker"] }
    /// `.firstMatch`: a toolbar button's identifier resolves to more than one accessibility node
    /// (the wrapping bar-item container and the nested button both carry it) — same class of issue
    /// as `ProjectDetailScreen.deleteCodebaseConfirmButton`.
    var createButton: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "stateConfig.createButton").firstMatch
    }

    // MARK: - Settings tab (`StateDiagramSidebar` — call `openSettingsTab()` first)

    var settingsScopePicker: XCUIElement { app.descendants(matching: .any)["diagram.stateSettings.scopePicker"] }
    var settingsVariablePicker: XCUIElement { app.descendants(matching: .any)["diagram.stateSettings.variablePicker"] }
    var settingsApplyButton: XCUIElement { app.buttons["diagram.stateSettings.applyButton"] }
}
