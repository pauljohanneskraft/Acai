import XCTest

/// A row's Rename action: a context menu on every platform — renaming is neither destructive nor
/// frequent enough for a swipe action, so there is no compact-width shortcut to it.
@MainActor
struct RowRenameAffordance {
    let app: XCUIApplication

    /// Reveals `row`'s Rename action and taps it, leaving the in-row text field focused.
    func tapRename(
        on row: XCUIElement, _ description: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        #if os(macOS)
        // Window-scoped: the system Edit menu exposes its own items to an unscoped query too.
        let rename = app.windows.firstMatch.descendants(matching: .any)["Rename"]
        row.reveal(description, until: rename, file: file, line: line) { $0.rightClick() }
        #else
        let rename = app.buttons["Rename"]
        row.reveal(description, until: rename, file: file, line: line) { $0.press(forDuration: 1.5) }
        #endif
        rename.tapWhenReady(
            "\(description)'s Rename action (if its detail screen opened instead, the reveal gesture "
                + "registered as a tap)",
            file: file, line: line
        )
    }
}
