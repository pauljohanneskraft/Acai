import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension Animation {
    static let canvasPan = Animation.easeInOut(duration: 0.2)
    static let disclosure = Animation.easeInOut(duration: 0.15)

    /// Never `nil`: a sidebar outline change needs an active transaction even when motion is reduced.
    @MainActor static var outlineChange: Animation {
        SystemMotionPreference().reducesMotion ? .linear(duration: 0) : .default
    }

    func respecting(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : self
    }
}

/// The system Reduce Motion setting, for code outside a view's environment.
@MainActor
struct SystemMotionPreference {
    var reducesMotion: Bool {
        #if os(macOS)
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #else
        UIAccessibility.isReduceMotionEnabled
        #endif
    }
}
