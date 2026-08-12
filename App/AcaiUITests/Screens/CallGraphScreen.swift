import XCTest

/// Adds Call Graph-specific accessors (canvas method nodes, the scope-selection config sheet, and
/// the Settings tab's live scope form and the selection-scoped Inspector) to
/// `DiagramScreenBase`'s shared toolbar/sidebar accessors.
final class CallGraphScreen: DiagramScreenBase {
    /// A method's box, by its `CallGraph.Node.id` (`"Type.method"`) — mirrors
    /// `ClassDiagramScreen.typeNode`, same "keyed by name, no stable id" caveat.
    func node(id: String) -> XCUIElement {
        app.descendants(matching: .any)["diagram.callGraphNode.\(id)"]
    }

    // MARK: - Config sheet (`CallGraphConfigSheet`, the creation-time flow from `CodebaseDetailView`)

    var scopePicker: XCUIElement { app.descendants(matching: .any)["callGraphConfig.scopePicker"] }
    var createButton: XCUIElement { app.descendants(matching: .any)["callGraphConfig.createButton"] }

    // MARK: - Settings tab (`CallGraphSidebar` — call `openSettingsTab()` first)

    var settingsScopePicker: XCUIElement { app.descendants(matching: .any)["diagram.callGraphSettings.scopePicker"] }
    var settingsApplyButton: XCUIElement { app.buttons["diagram.callGraphSettings.applyButton"] }
}
