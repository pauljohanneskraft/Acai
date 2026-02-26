import SwiftUI

/// Preference key for collecting measured sizes of custom diagram node views.
struct CustomNodeSizePreferenceKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [UUID: CGSize] = [:]

    static func reduce(value: inout [UUID: CGSize], nextValue: () -> [UUID: CGSize]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
