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

    /// Shown once a first reindex finishes, until hidden; `guidedRouteButton` brings it back.
    var guidedRouteCard: XCUIElement { app.descendants(matching: .any)["guidedRoute.card"] }
    var guidedRouteHideButton: XCUIElement { app.buttons["guidedRoute.hideButton"] }
    var guidedRouteButton: XCUIElement { app.buttons["codebaseDetail.guidedRouteButton"] }

    /// `kind` is a `GuidedRouteStop.Kind.rawValue` (`"entryPoint"`, `"mostDependedUpon"`, `"mostComplex"`).
    func guidedRouteStop(kind: String) -> XCUIElement {
        app.descendants(matching: .any)["guidedRoute.stop.\(kind)"]
    }

    /// The card sits below the diagram grid, so it can start past the bottom of the pane. Checks the
    /// frame rather than `isHittable`, which on macOS stays `true` for a partly clipped element.
    func scrollIntoView(
        _ element: XCUIElement, _ description: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        element.waitOrFail(description, file: file, line: line)
        // Not `firstMatch`: on macOS that is the sidebar's list.
        let scrollView = app.scrollViews.containing(.any, identifier: "guidedRoute.card").firstMatch
        for _ in 0..<8 where element.frame.maxY > scrollView.frame.maxY {
            #if os(macOS)
            scrollView.scroll(byDeltaX: 0, deltaY: -60)
            #else
            scrollView.swipeUp()
            #endif
        }
        XCTAssertLessThanOrEqual(
            element.frame.maxY, scrollView.frame.maxY, "\(description) never scrolled fully into view",
            file: file, line: line
        )
    }

    /// Opens a stop's diagram, tapping exactly once and asserting the detail pane navigated away.
    @discardableResult
    func openGuidedRouteStop<Screen: DiagramScreenBase>(
        kind: String, as screen: Screen.Type, file: StaticString = #filePath, line: UInt = #line
    ) -> Screen {
        let stop = guidedRouteStop(kind: kind)
        scrollIntoView(stop, "the \(kind) guided route stop", file: file, line: line)
        stop.tapWhenReady("the \(kind) guided route stop", file: file, line: line)
        stop.waitForDisappearanceOrFail(
            "the codebase screen after opening the \(kind) guided route stop", file: file, line: line
        )
        return Screen(app: app)
    }

    func hideGuidedRoute(file: StaticString = #filePath, line: UInt = #line) {
        scrollIntoView(guidedRouteHideButton, "the guided route Hide button", file: file, line: line)
        guidedRouteHideButton.tapWhenReady("Hide the guided route", file: file, line: line)
        guidedRouteCard.waitForDisappearanceOrFail("the hidden guided route card", file: file, line: line)
    }

    func showGuidedRoute(file: StaticString = #filePath, line: UInt = #line) {
        guidedRouteButton.tapWhenReady("Guided Route", file: file, line: line)
        guidedRouteCard.waitOrFail("the guided route card brought back", file: file, line: line)
    }

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
