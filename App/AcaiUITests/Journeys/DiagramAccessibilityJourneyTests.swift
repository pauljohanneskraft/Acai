import XCTest

/// The canvas is drawn rather than built from controls, so nothing on it reaches VoiceOver unless the
/// app describes it — these check that nodes and edges do, as the accessibility tree actually exposes them.
@MainActor
final class DiagramAccessibilityJourneyTests: UIJourneyTestCase {

    func testClassDiagramNodesAndRelationshipsDescribeThemselves() {
        let diagram = openIndexedSeededCodebase(analysis: .parsed)
            .createDiagram(type: "class", as: ClassDiagramScreen.self)

        diagram.describedTypeNode(named: "Base").waitOrFail("the described Base type node", timeout: .uiWork)
        diagram.describedTypeNode(named: "Derived").waitOrFail("the described Derived type node")
        diagram.relationship(from: "Derived", to: "Base", describing: "Inheritance")
            .waitOrFail("the Derived → Base relationship, described as inheritance")
    }

    func testCallGraphNodesAndCallsDescribeThemselves() {
        let callGraph = openIndexedSeededCodebase().openDiagramConfiguration(
            type: "callGraph", as: CallGraphScreen.self, until: { $0.createButton }
        )
        callGraph.createButton.tapWhenReady("the call graph configuration's Create button")

        callGraph.describedNode(id: "Derived.doWork").waitOrFail("the described Derived.doWork node", timeout: .uiWork)
        callGraph.describedCall.waitOrFail("a described call edge")
    }
}
