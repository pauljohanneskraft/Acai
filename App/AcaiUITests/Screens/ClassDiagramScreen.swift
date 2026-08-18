import XCTest

final class ClassDiagramScreen: DiagramScreenBase {
    /// Keyed by `TypeDeclaration.name` — `TypeNodeView` has no separate stable id of its own.
    func typeNode(named name: String) -> XCUIElement {
        app.descendants(matching: .any)["diagram.typeNode.\(name)"]
    }
}
