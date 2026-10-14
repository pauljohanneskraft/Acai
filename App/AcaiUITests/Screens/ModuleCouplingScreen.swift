import XCTest

/// The chart's own marks are `Charts`-drawn and matched by their accessibility labels, so what this
/// adds over `DiagramScreenBase` is the empty state and the Reindex it offers.
final class ModuleCouplingScreen: DiagramScreenBase {
    var emptyState: XCUIElement { app.descendants(matching: .any)["moduleCoupling.emptyState"].firstMatch }
    var reindexButton: XCUIElement { app.buttons["moduleCoupling.reindexButton"].firstMatch }
    var reindex: AsyncOperation { AsyncOperation(app: app, identifierPrefix: "moduleCoupling.reindex") }

    func reindexFromEmptyState(file: StaticString = #filePath, line: UInt = #line) {
        reindexButton.tapWhenReady("Reindex", file: file, line: line)
        reindex.waitUntilLoaded("Reindexing from the module coupling chart", file: file, line: line)
    }
}
