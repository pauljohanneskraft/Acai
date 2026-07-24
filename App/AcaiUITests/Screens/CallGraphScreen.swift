import XCTest

/// Adds Call Graph-specific accessors (canvas method nodes, the scope-selection config sheet) to
/// `DiagramScreenBase`'s shared toolbar accessors. See `TESTING_ARCHITECTURE.md` Layer 2.
final class CallGraphScreen: DiagramScreenBase {
    /// A method's box, by its `CallGraph.Node.id` (`"Type.method"`) — mirrors
    /// `ClassDiagramScreen.typeNode`, same "keyed by name, no stable id" caveat.
    func node(id: String) -> XCUIElement {
        app.descendants(matching: .any)["diagram.callGraphNode.\(id)"]
    }

    // MARK: - Config sheet (`CallGraphConfigSheet`)

    var scopePicker: XCUIElement { app.descendants(matching: .any)["callGraphConfig.scopePicker"] }
    var createButton: XCUIElement { app.descendants(matching: .any)["callGraphConfig.createButton"] }
}
