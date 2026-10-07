import XCTest

/// A row's Delete action: a context menu on macOS and iPad, a swipe action on iPhone's compact width.
@MainActor
struct RowDeleteAffordance {
    let app: XCUIApplication

    /// Reveals `row`'s Delete action and taps it, leaving its confirmation on screen for the caller.
    func tapDelete(
        on row: XCUIElement, _ description: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        #if os(macOS)
        // Window-scoped: the system Edit menu's own "Delete" item also matches an unscoped query.
        let delete = app.windows.firstMatch.descendants(matching: .any)["Delete"]
        row.reveal(description, until: delete, file: file, line: line) { $0.rightClick() }
        #else
        let delete = app.buttons["Delete"]
        if SnapshotPlatform().usesCompactLayout {
            // Never repeated: a second swipe on an open row can full-swipe, which performs the action.
            row.waitUntilReady(description, file: file, line: line)
            SystemBanners().dismiss(file: file, line: line)
            row.swipeLeft()
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
