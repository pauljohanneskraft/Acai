import XCTest

final class CallGraphScreen: DiagramScreenBase {
    /// Keyed by `CallGraph.Node.id` (`"Type.method"`) — no separate stable id, same caveat as
    /// `ClassDiagramScreen.typeNode`.
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
