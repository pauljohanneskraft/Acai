import XCTest

/// Adds Sequence Diagram-specific accessors (canvas participants, the entry-point config sheet) to
/// `DiagramScreenBase`'s shared toolbar accessors. See `TESTING_ARCHITECTURE.md` Layer 2.
final class SequenceDiagramScreen: DiagramScreenBase {
    /// A participant's lifeline header, by its `SequenceDiagram.Participant.name` — mirrors
    /// `ClassDiagramScreen.typeNode`, same "keyed by name, no stable id" caveat.
    func participant(named name: String) -> XCUIElement {
        app.descendants(matching: .any)["diagram.sequenceParticipant.\(name)"]
    }

    // MARK: - Config sheet (`SequenceConfigSheet`)

    var typePicker: XCUIElement { app.descendants(matching: .any)["sequenceConfig.typePicker"] }
    var methodPicker: XCUIElement { app.descendants(matching: .any)["sequenceConfig.methodPicker"] }
    /// `.firstMatch`: a toolbar button's identifier resolves to more than one accessibility node
    /// (the wrapping bar-item container and the nested button both carry it) — same class of issue
    /// as `ProjectDetailScreen.deleteCodebaseConfirmButton`.
    var nextButton: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "sequenceConfig.nextButton").firstMatch
    }
    var createButton: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "sequenceConfig.createButton").firstMatch
    }
}
