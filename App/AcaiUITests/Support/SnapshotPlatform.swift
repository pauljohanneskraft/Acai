import Foundation
#if !os(macOS)
import UIKit
#endif

/// iPhone vs. iPad needs a runtime check (`UIDevice.current.userInterfaceIdiom`), not a
/// compile-time `#if`: the same iOS UI test binary runs against both destinations.
@MainActor
struct SnapshotPlatform {
    let name: String

    init() {
        #if os(macOS)
        name = "macOS"
        #else
        switch UIDevice.current.userInterfaceIdiom {
        case .pad: name = "iPad"
        default: name = "iPhone"
        }
        #endif
    }

    /// Whether the app lays out in its compact horizontal size class: a navigation stack over the
    /// sidebar and a "+" menu in place of inline actions. Journeys run full screen on fixed devices —
    /// iPhone in portrait, iPad pinned to landscape by `UIJourneyTestCase` — so the device decides it; a
    /// journey that runs iPad in a multitasking width must not rely on this. Branch on this rather than
    /// on whether an element happens to exist yet.
    var usesCompactLayout: Bool { name == "iPhone" }
}
