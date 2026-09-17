import XCTest

@MainActor
final class CodebaseDetailScreen {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    var reindexButton: XCUIElement { app.buttons["codebaseDetail.reindexButton"] }
    var reindexOperation: AsyncOperation { AsyncOperation(app: app, identifierPrefix: "codebaseDetail.reindex") }
    var refSwitchOperation: AsyncOperation { AsyncOperation(app: app, identifierPrefix: "codebaseDetail.refSwitch") }
    var pullOperation: AsyncOperation { AsyncOperation(app: app, identifierPrefix: "codebaseDetail.pull") }

    var staleBanner: XCUIElement { app.descendants(matching: .any)["codebaseDetail.staleBanner"] }
    var staleBannerReindexButton: XCUIElement { app.buttons["codebaseDetail.staleBanner.reindexButton"] }
    var staleBannerReindexOperation: AsyncOperation {
        AsyncOperation(app: app, identifierPrefix: "codebaseDetail.staleBanner.reindex")
    }

    func reindex(file: StaticString = #filePath, line: UInt = #line) {
        reindexButton.tapWhenReady("Reindex", file: file, line: line)
        reindexOperation.waitUntilLoaded("Reindexing the codebase", file: file, line: line)
    }

    /// `type` is a `DiagramType.rawValue` (e.g. `"class"`, `"sequence"`, `"callGraph"`).
    func diagramButton(type: String) -> XCUIElement {
        app.buttons["codebaseDetail.diagramButton.\(type)"]
    }

    /// Creates a diagram whose card opens it directly (class, package, module coupling, hotspot).
    /// Taps exactly once — the card creates a diagram on every tap — and asserts the detail pane
    /// actually navigated away, the symptom a dropped selection update leaves behind.
    @discardableResult
    func createDiagram<Screen: DiagramScreenBase>(
        type: String, as screen: Screen.Type, file: StaticString = #filePath, line: UInt = #line
    ) -> Screen {
        let button = diagramButton(type: type)
        button.tapWhenReady("the \(type) diagram card", file: file, line: line)
        button.waitForDisappearanceOrFail(
            "the codebase screen after creating a \(type) diagram (the new diagram was never opened)",
            file: file, line: line
        )
        return Screen(app: app)
    }

    /// Opens the configuration sheet of a diagram type that asks before creating (sequence, state,
    /// call graph). Opening the sheet has no side effect, so the tap may be retried.
    @discardableResult
    func openDiagramConfiguration<Screen: DiagramScreenBase>(
        type: String, as screen: Screen.Type, until sheetControl: (Screen) -> XCUIElement,
        file: StaticString = #filePath, line: UInt = #line
    ) -> Screen {
        let diagram = Screen(app: app)
        diagramButton(type: type).tap(
            "the \(type) diagram card", until: sheetControl(diagram), file: file, line: line
        )
        return diagram
    }

    /// Opens `QueryView`. Shown only once the codebase has an artifact — same gating as
    /// `diagramButton`, so it only appears after a successful reindex.
    var queryButton: XCUIElement { app.buttons["codebaseDetail.queryButton"] }

    /// Shown instead of `reindexButton` for a GitHub-backed codebase.
    var refPicker: XCUIElement { app.descendants(matching: .any)["codebaseDetail.refPicker"] }
    var pullButton: XCUIElement { app.buttons["codebaseDetail.pullButton"] }

    func switchRef(to label: String, file: StaticString = #filePath, line: UInt = #line) {
        refPicker.choose(label, in: app, file: file, line: line)
        refSwitchOperation.waitUntilLoaded("Switching to \(label)", file: file, line: line)
    }

    var deleteCodebaseButton: XCUIElement { app.buttons["codebaseDetail.deleteCodebaseButton"] }
    var deleteCodebaseConfirmButton: XCUIElement {
        app.buttons.matching(identifier: "codebaseDetail.codebase.delete.confirmButton").firstMatch
    }
}
