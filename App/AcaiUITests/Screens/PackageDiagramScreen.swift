import XCTest

/// Adds Package Diagram-specific accessors (canvas package boxes) to `DiagramScreenBase`'s shared
/// toolbar accessors. No config sheet — a package diagram is added directly, spanning every build
/// module in the codebase. See `TESTING_ARCHITECTURE.md` Layer 2.
final class PackageDiagramScreen: DiagramScreenBase {
    /// A package's box, by its module name — mirrors `ClassDiagramScreen.typeNode`, same
    /// "keyed by name, no stable id" caveat.
    func containerNode(named name: String) -> XCUIElement {
        app.descendants(matching: .any)["diagram.containerNode.\(name)"]
    }
}
