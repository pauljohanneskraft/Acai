import XCTest

/// A row's own delete affordance, which is a different presentation per platform: a `.contextMenu` on
/// macOS (right-click) and on iPad (long press — iPad's regular width renders rows in a `LazyVStack`,
/// not a native `List`, so `.swipeActions` never existed there), and a `.swipeActions` swipe on
/// iPhone's compact width. The sidebar's rows and a project's codebase rows share all of it.
@MainActor
struct RowDeleteAffordance {
    let app: XCUIApplication

    /// Reveals `row`'s Delete action and taps it, leaving its confirmation on screen for the caller.
    func tapDelete(
        on row: XCUIElement, _ description: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        #if os(macOS)
        // Window-scoped, not `app.descendants`: the system Edit menu's standard "Delete" item
        // (identifier `delete:`) also matches an unscoped query, unlike our own `trash`-identified
        // item, which only lives under the window.
        let delete = app.windows.firstMatch.descendants(matching: .any)["Delete"]
        row.reveal(description, until: delete, file: file, line: line) { $0.rightClick() }
        #else
        let delete = app.buttons["Delete"]
        if SnapshotPlatform().usesCompactLayout {
            row.reveal(description, until: delete, file: file, line: line) { $0.swipeLeft() }
        } else {
            row.reveal(description, until: delete, file: file, line: line) { $0.press(forDuration: 1.5) }
        }
        #endif
        delete.tapWhenReady(
            "\(description)'s Delete action (if its detail screen opened instead, the reveal gesture "
                + "registered as a tap)",
            file: file, line: line
        )
    }
}
