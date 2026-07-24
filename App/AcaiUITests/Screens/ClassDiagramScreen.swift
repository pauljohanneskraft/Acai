import XCTest

/// Adds Class Diagram-specific accessors (canvas type nodes) to `DiagramScreenBase`'s shared
/// toolbar accessors. See `TESTING_ARCHITECTURE.md` Layer 2.
final class ClassDiagramScreen: DiagramScreenBase {
    /// A type's canvas box, by its `TypeDeclaration.name` — `TypeNodeView` has no separate stable
    /// id of its own to key on (see its `.accessibilityIdentifier` call site's comment).
    func typeNode(named name: String) -> XCUIElement {
        app.descendants(matching: .any)["diagram.typeNode.\(name)"]
    }

    /// Present once the sidebar is open on the Inspector tab — reached by double-tapping a node
    /// (`ClassDiagramView`'s `.onTapGesture(count: 2)`), which selects it and switches tabs in one
    /// action.
    var inspectorContent: XCUIElement { app.descendants(matching: .any)["diagram.sidebarContent.inspector"] }
}
