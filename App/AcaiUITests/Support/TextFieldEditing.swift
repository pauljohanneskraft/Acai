import XCTest

@MainActor
extension XCUIElement {
    /// `typeText` alone would just append to an already-populated field.
    func clearAndTypeText(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        focus("the text field", file: file, line: line)
        clearEnteredText(file: file, line: line)
        typeText(text)
    }

    /// An empty field reports its placeholder as its value, so the two have to be compared.
    private var enteredText: String? {
        guard let text = value as? String, !text.isEmpty, text != placeholderValue else { return nil }
        return text
    }

    /// Each pass faces a narrower remainder, so a trailing-edge tap that landed mid-string clears it.
    private func clearEnteredText(attempts: Int = 3, file: StaticString, line: UInt) {
        for _ in 0..<attempts {
            guard let current = enteredText else { return }
            coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 10))
        }
        if let remaining = enteredText {
            XCTFail("the text field still held '\(remaining)' after clearing", file: file, line: line)
        }
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
        option.waitOrFail("option '\(label)'", timeout: timeout, file: file, line: line)
        // The option exists mid-presentation; `tap()` waits for the app to idle first, `isHittable` doesn't.
        #if os(iOS)
        // A loaded simulator can drop the tap and leave the menu open; picking the same option again is a
        // no-op, and the re-check keeps a menu that closed late from being tapped through.
        let attempts = 3
        for attempt in 0..<attempts {
            SystemBanners().dismiss(file: file, line: line)
            if attempt > 0, !(option.exists && option.isHittable) { break }
            option.tap()
            if option.waitForNonExistence(timeout: .uiTransition / Double(attempts)) { break }
        }
        #else
        SystemBanners().dismiss(file: file, line: line)
        option.tap()
        #endif
        return option
    }
}
