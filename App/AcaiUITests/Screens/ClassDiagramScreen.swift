import XCTest

/// Adds Class Diagram-specific accessors (canvas type nodes) to `DiagramScreenBase`'s shared
/// toolbar/sidebar accessors (`inspectorContent` is inherited from there — every diagram type's
/// sidebar tags its Inspector tab identically).
final class ClassDiagramScreen: DiagramScreenBase {
    /// A type's canvas box, by its `TypeDeclaration.name` — `TypeNodeView` has no separate stable
    /// id of its own to key on (see its `.accessibilityIdentifier` call site's comment).
    func typeNode(named name: String) -> XCUIElement {
        app.descendants(matching: .any)["diagram.typeNode.\(name)"]
    }
}
