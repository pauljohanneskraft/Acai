import SwiftUI

extension DynamicTypeSize {
    /// A deterministic scale relative to `.large` (the system default), approximating Apple's own
    /// `.body` content-size-category ratios. Every explicitly-sized font in this module multiplies by
    /// this instead of leaning on `@ScaledMetric`/semantic text styles' automatic scaling: that
    /// automatic scaling silently no-ops on macOS — `dynamicTypeSize(_:)` sets the environment value,
    /// but AppKit's text pipeline doesn't read it the way UIKit's does, so a size forced in a UI test
    /// (or a real user's system text-size preference) visibly grows iOS/iPadOS text while leaving
    /// macOS text untouched. Multiplying explicitly keeps all three platforms in lockstep.
    public var scaleFactor: CGFloat {
        Self.scaleFactorsBySize[self] ?? 1
    }

    private static let scaleFactorsBySize: [DynamicTypeSize: CGFloat] = [
        .xSmall: 0.82,
        .small: 0.88,
        .medium: 0.95,
        .large: 1,
        .xLarge: 1.12,
        .xxLarge: 1.24,
        .xxxLarge: 1.36,
        .accessibility1: 1.64,
        .accessibility2: 1.95,
        .accessibility3: 2.35,
        .accessibility4: 2.76,
        .accessibility5: 3.12
    ]
}
