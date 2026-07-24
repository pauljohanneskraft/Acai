import XCTest

/// Adds State Diagram-specific accessors (canvas state nodes, the variable-selection config sheet)
/// to `DiagramScreenBase`'s shared toolbar accessors. See `TESTING_ARCHITECTURE.md` Layer 2.
final class StateDiagramScreen: DiagramScreenBase {
    /// A state box, by its `StateDiagram.State.name` — mirrors `ClassDiagramScreen.typeNode`, same
    /// "keyed by name, no stable id" caveat.
    func stateNode(named name: String) -> XCUIElement {
        app.descendants(matching: .any)["diagram.stateNode.\(name)"]
    }

    // MARK: - Config sheet (`StateConfigSheet`)

    var scopePicker: XCUIElement { app.descendants(matching: .any)["stateConfig.scopePicker"] }
    var variablePicker: XCUIElement { app.descendants(matching: .any)["stateConfig.variablePicker"] }
    /// `.firstMatch`: a toolbar button's identifier resolves to more than one accessibility node
    /// (the wrapping bar-item container and the nested button both carry it) — same class of issue
    /// as `ProjectDetailScreen.deleteCodebaseConfirmButton`.
    var createButton: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "stateConfig.createButton").firstMatch
    }
}
