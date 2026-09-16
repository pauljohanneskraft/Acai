import XCTest

@MainActor
final class OpenSeededProjectGenerateDiagramTests: UIJourneyTestCase {
    func testGenerateClassDiagramFromSeededCodebase() throws {
        let codebaseDetail = openIndexedSeededCodebase(analysis: .parsed)
        let diagram = codebaseDetail.createDiagram(type: "class", as: ClassDiagramScreen.self)

        diagram.typeNode(named: "Base").waitOrFail("the Base type node", timeout: .uiWork)
        XCTAssertTrue(diagram.typeNode(named: "Derived").exists, "Derived should be drawn alongside Base")
    }
}
