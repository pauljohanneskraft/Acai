import SwiftUI

#if os(macOS)
import AppKit

private struct CursorArea: ViewModifier {
    let cursor: NSCursor

    func body(content: Content) -> some View {
        content.onHover { isHovering in
            if isHovering {
                cursor.push()
            } else {
                cursor.pop()
            }
        }
    }

}

extension View {
    func cursorOnHover(_ cursor: NSCursor) -> some View {
        modifier(CursorArea(cursor: cursor))
    }
}

#endif
