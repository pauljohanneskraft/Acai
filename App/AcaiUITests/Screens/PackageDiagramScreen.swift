import XCTest

final class PackageDiagramScreen: DiagramScreenBase {
    /// Keyed by module name — no separate stable id, same caveat as `ClassDiagramScreen.typeNode`.
    func containerNode(named name: String) -> XCUIElement {
        app.descendants(matching: .any)["diagram.containerNode.\(name)"]
    }
}
