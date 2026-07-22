import CoreGraphics
import XCTest

/// Accessors for the chrome that's actually common across every diagram type's toolbar today
/// (`UndoRedoToolbarButtons`, Fit to View, the sidebar toggle) — see `TESTING_ARCHITECTURE.md`
/// Layer 2 for why this deliberately stays narrow rather than a full unified sidebar-tab base
/// class: `USABILITY_IMPROVEMENTS.md` Part 6 documents that today's diagram types have three
/// genuinely different sidebar architectures, so a shared Settings/Inspector/Compare accessor set
/// would encode a unification that hasn't shipped yet.
class DiagramScreenBase {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    var undoButton: XCUIElement { app.buttons["diagram.undoButton"] }
    var redoButton: XCUIElement { app.buttons["diagram.redoButton"] }
    var fitToViewButton: XCUIElement { app.buttons["diagram.fitToViewButton"] }
    var sidebarToggleButton: XCUIElement { app.buttons["diagram.sidebarToggleButton"] }
    /// The navigation bar's back button, for returning to `CodebaseDetailScreen` from a diagram.
    var backButton: XCUIElement { app.buttons["BackButton"] }

    // MARK: - Compare vs git (`DeltaComparisonBar`, shared by every diagram type)

    var compareToggle: XCUIElement { app.descendants(matching: .any)["delta.toggle"] }
    var compareRefField: XCUIElement { app.descendants(matching: .any)["delta.refField"] }
    var compareLoadedIndicator: XCUIElement { app.descendants(matching: .any)["delta.loaded"] }
    var compareErrorIndicator: XCUIElement { app.descendants(matching: .any)["delta.error"] }

    /// Taps the actual switch, not `compareToggle.tap()`. Found empirically (via an exported
    /// accessibility-tree dump): SwiftUI's `Toggle(isOn:) { Label(...) }` exposes accessibility as
    /// one wide combined `Switch` element carrying `delta.toggle` (spanning the label *and* the
    /// switch, e.g. 358pt wide), with the actual hittable control being a separate, unlabeled inner
    /// `Switch` positioned only at the trailing edge (e.g. the rightmost ~63pt) — matching how
    /// SwiftUI documents accessibility identifiers as attaching to the logical control while the
    /// underlying platform control keeps its own hit-testable geometry. `.tap()` on the outer
    /// element synthesizes a tap at *its* center, landing on the label rather than the switch. A
    /// normalized-offset tap near the trailing edge lands on the real inner switch instead.
    func tapCompareToggle() {
        compareToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    }
}
