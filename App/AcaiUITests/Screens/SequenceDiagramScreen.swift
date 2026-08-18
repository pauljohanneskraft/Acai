import XCTest

final class SequenceDiagramScreen: DiagramScreenBase {
    /// Keyed by `SequenceDiagram.Participant.name` — no separate stable id, same caveat as
    /// `ClassDiagramScreen.typeNode`.
    func participant(named name: String) -> XCUIElement {
        app.descendants(matching: .any)["diagram.sequenceParticipant.\(name)"]
    }

    // MARK: - Config sheet (`SequenceConfigSheet`, the creation-time flow from `CodebaseDetailView`)

    var typePicker: XCUIElement { app.descendants(matching: .any)["sequenceConfig.typePicker"] }
    var methodPicker: XCUIElement { app.descendants(matching: .any)["sequenceConfig.methodPicker"] }
    /// `.firstMatch`: a toolbar button's identifier resolves to more than one accessibility node
    /// (the wrapping bar-item container and the nested button both carry it).
    var nextButton: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "sequenceConfig.nextButton").firstMatch
    }
    var createButton: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "sequenceConfig.createButton").firstMatch
    }

    // MARK: - Settings tab (`SequenceDiagramSidebar` — call `openSettingsTab()` first)

    var settingsTypePicker: XCUIElement { app.descendants(matching: .any)["diagram.sequenceSettings.typePicker"] }
    var settingsMethodPicker: XCUIElement { app.descendants(matching: .any)["diagram.sequenceSettings.methodPicker"] }
    var settingsApplyButton: XCUIElement { app.buttons["diagram.sequenceSettings.applyButton"] }
    var settingsApplyResolvedMappingButton: XCUIElement {
        app.buttons["diagram.sequenceSettings.applyResolvedMappingButton"]
    }
}
