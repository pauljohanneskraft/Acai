import Foundation
#if !os(macOS)
import UIKit
#endif

/// The platform-name path segment of the `<platform>/<ViewType>/<state>.png` golden layout
/// (`TESTING_ARCHITECTURE.md` Layer 2) — computed once at runtime so the single shared
/// `Acai-iOSUITests` binary produces the right segment whether it's launched on an iPhone or iPad
/// destination, and the separate `Acai-macOSUITests` binary produces its own. A real instantiated
/// value (`SnapshotPlatform().name`), never a static-function namespace, per `CLAUDE.md`'s style
/// rule.
///
/// iPhone vs. iPad must be a runtime check (`UIDevice.current.userInterfaceIdiom`) rather than a
/// compile-time `#if`: the same iOS UI test binary runs against both destinations, only the
/// macOS/iOS split is known at compile time.
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
}
