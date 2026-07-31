import Foundation

/// A project-level record of "known, not fixing this one" findings — deliberately a plain,
/// diffable, versioned file rather than hidden app state or `UserDefaults`, so a suppression is a
/// visible, git-reviewable decision (the same role SwiftLint's own baseline file or an
/// `.eslintignore` plays for their domains), not a silent client-side toggle. Suppressed findings
/// disappear from the default Findings view; a toggle shows "show suppressed too."
struct FindingsSuppressionBaseline: Codable, Equatable, Sendable {
    /// Bumped on an incompatible format change — an older or unreadable file is
    /// treated as "nothing suppressed yet" rather than mis-parsed or thrown away with an error the
    /// user can't act on.
    var formatVersion = 1
    /// The suppressed findings' stable `Finding.id`s. Not stable across a code edit that shifts the
    /// flagged line — the same limitation a SwiftLint baseline file has; stated here rather than
    /// silently discovered.
    var suppressedFindingIDs: Set<String> = []
}
