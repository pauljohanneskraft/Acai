import Foundation

/// Deliberately a plain, diffable, versioned file rather than hidden app state or `UserDefaults`,
/// so a suppression is a visible, git-reviewable decision, not a silent client-side toggle.
struct FindingsSuppressionBaseline: Codable, Equatable, Sendable {
    var formatVersion = 1
    /// Not stable across a code edit that shifts the flagged line.
    var suppressedFindingIDs: Set<String> = []
}
