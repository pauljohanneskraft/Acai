import XCTest

final class ModuleCouplingScreen: DiagramScreenBase {
    var emptyState: XCUIElement { app.descendants(matching: .any)["moduleCoupling.emptyState"].firstMatch }
    var reindexButton: XCUIElement { app.buttons["moduleCoupling.reindexButton"].firstMatch }
    var reindex: AsyncOperation { AsyncOperation(app: app, identifierPrefix: "moduleCoupling.reindex") }

    func reindexFromEmptyState(file: StaticString = #filePath, line: UInt = #line) {
        reindexButton.tapWhenReady("Reindex", file: file, line: line)
        reindex.waitUntilLoaded("Reindexing from the module coupling chart", file: file, line: line)
    }
}
