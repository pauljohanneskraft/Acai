import XCTest

@MainActor
extension XCUIElement {
    /// `typeText` alone would just append to an already-populated field.
    func clearAndTypeText(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        tapWhenReady("the text field", file: file, line: line)
        // An empty field reports its placeholder as its value, so comparing the two is what tells
        // "has text" from "has a prompt" — otherwise every field pays a burst of deletes it doesn't need.
        if let currentValue = value as? String, !currentValue.isEmpty, currentValue != placeholderValue {
            // A plain `tap()` lands mid-string, so backspacing from there can leave a tail behind. Move
            // the cursor to the trailing edge first, then delete comfortably more than the length.
            coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count + 10))
        }
        typeText(text)
    }

    /// Picks an option from a `Picker`-rendered popup/menu (`self`) by its literal text. Matches
    /// `label` or `title`: a macOS popup button's `NSMenuItem` exposes its text via `title` with
    /// `label` empty, the opposite of iOS. Only tappable option types match — the same text as a
    /// static label elsewhere on screen (a findings row behind the sheet) is not the option.
    @discardableResult
    func choose(
        _ label: String, in app: XCUIApplication, timeout: TimeInterval = .uiTransition,
        file: StaticString = #filePath, line: UInt = #line
    ) -> XCUIElement {
        tapWhenReady("the control offering '\(label)'", file: file, line: line)
        let optionTypes: [XCUIElement.ElementType] = [.button, .menuItem, .cell]
        let option = app.descendants(matching: .any)
            .matching(NSPredicate(
                format: "(label == %@ OR title == %@) AND elementType IN %@",
                label, label, optionTypes.map(\.rawValue)))
            .firstMatch
        option.tapWhenReady("option '\(label)'", timeout: timeout, file: file, line: line)
        return option
    }
}
