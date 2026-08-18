import Foundation

/// Centralizes the default `waitForExistence(timeout:)` budgets, so future tuning is one edit
/// instead of another round of scattered per-call-site bumps.
struct UITestWaits {
    static let standard = UITestWaits()

    var short: TimeInterval = 10
    var long: TimeInterval = 30
}
