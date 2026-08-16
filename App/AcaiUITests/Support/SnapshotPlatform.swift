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
}
