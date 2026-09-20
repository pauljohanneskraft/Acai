import XCTest

final class CallGraphScreen: DiagramScreenBase {
    /// Keyed by `CallGraph.Node.id` (`"Type.method"`) — no separate stable id, same caveat as
    /// `ClassDiagramScreen.typeNode`.
    func node(id: String) -> XCUIElement {
        app.descendants(matching: .any)["diagram.callGraphNode.\(id)"]
    }

    /// A method node as VoiceOver reads it: labelled `Type.method` and carrying a non-empty description.
    func describedNode(id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ AND label == %@ AND value != nil AND value != ''",
            "diagram.callGraphNode.\(id)", id
        )).firstMatch
    }

    /// Any call edge VoiceOver can reach, whose label says it is a call and not just which ends it joins.
    var describedCall: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH 'diagram.callEdge.' AND label CONTAINS[c] 'call'"
        )).firstMatch
    }

    // MARK: - Config sheet (`CallGraphConfigSheet`, the creation-time flow from `CodebaseDetailView`)

    var scopePicker: XCUIElement { app.descendants(matching: .any)["callGraphConfig.scopePicker"] }
    var createButton: XCUIElement { app.descendants(matching: .any)["callGraphConfig.createButton"] }

    // MARK: - Settings tab (`CallGraphSidebar` — call `openSettingsTab()` first)

    var settingsScopePicker: XCUIElement { app.descendants(matching: .any)["diagram.callGraphSettings.scopePicker"] }
    var settingsApplyButton: XCUIElement { app.buttons["diagram.callGraphSettings.applyButton"] }
}
