import SwiftUI

/// Preference key for collecting measured sizes of UML class box views.
struct NodeSizePreferenceKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [String: CGSize] = [:]

    static func reduce(value: inout [String: CGSize], nextValue: () -> [String: CGSize]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
