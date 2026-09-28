import Testing
import AcaiCore
import AcaiRender

/// The rule behind the sidebar's Focus toggle: what enabling and disabling focus does to the
/// configuration the diagram is rendered from.
@Suite("Class diagram focus rule")
struct ClassDiagramFocusRuleTests {

    @Test func aDiagramIsUnfocusedUntilFocusIsTurnedOn() {
        var config = ClassDiagramConfiguration()
        #expect(!config.isFocused)

        config.setFocused(true, rootTypeName: "Widget")
        #expect(config.isFocused)
        #expect(config.focus?.rootTypeName == "Widget")
    }

    @Test func focusingStartsFromEveryDefault() throws {
        var config = ClassDiagramConfiguration()
        config.setFocused(true, rootTypeName: "Widget")

        let focus = try #require(config.focus)
        #expect(focus.maxDepth == nil)
        #expect(focus.direction == .dependencies)
        #expect(focus.includedRelationshipKinds == Set(Relationship.Kind.allCases))
        #expect(focus.includeInterconnections)
    }

    /// The toggle is offered before a root can be picked (the picker appears only once focus is on),
    /// so an empty root is the honest starting state rather than a crash or a silent no-op.
    @Test func focusingWithNoTypeToStartFromUsesAnEmptyRoot() {
        var config = ClassDiagramConfiguration()
        config.setFocused(true, rootTypeName: nil)
        #expect(config.focus?.rootTypeName.isEmpty == true)
        #expect(config.isFocused)
    }

    @Test func unfocusingDropsTheWholeFocusRatherThanKeepingItsRoot() {
        var config = ClassDiagramConfiguration()
        config.focus = FocusConfiguration(rootTypeName: "Widget", maxDepth: 2, direction: .both)

        config.setFocused(false, rootTypeName: "Widget")
        #expect(config.focus == nil)
        #expect(!config.isFocused)
    }

    /// Focusing an already-focused diagram must not reset the root, depth or direction the user set.
    @Test func focusingAnAlreadyFocusedDiagramKeepsItsSettings() {
        var config = ClassDiagramConfiguration()
        config.focus = FocusConfiguration(rootTypeName: "Widget", maxDepth: 2, direction: .dependents)

        config.setFocused(true, rootTypeName: "Other")
        #expect(config.focus?.rootTypeName == "Widget")
        #expect(config.focus?.maxDepth == 2)
        #expect(config.focus?.direction == .dependents)
    }

    /// Focus is orthogonal to the rest of the configuration — turning it off leaves everything the
    /// user configured beside it alone.
    @Test func togglingFocusTouchesNothingElse() {
        var config = ClassDiagramConfiguration()
        config.grouping = .directory
        config.showMethods = false
        config.minimumAccessLevel = .public

        config.setFocused(true, rootTypeName: "Widget")
        config.setFocused(false, rootTypeName: "Widget")

        #expect(config.grouping == .directory)
        #expect(!config.showMethods)
        #expect(config.minimumAccessLevel == .public)
    }
}
