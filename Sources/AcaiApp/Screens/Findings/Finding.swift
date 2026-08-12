import Foundation
import AcaiCore

/// One row in the project-level Findings view — a quality violation, a dead-code candidate,
/// or a health-check parse diagnostic, normalized to one shape so every flaw-detection lens the
/// engine produces can be sorted, filtered, and resolved through `CodeElementReference`
/// identically, regardless of which scan produced it. Previously each lens lived buried inside
/// `CodebaseDetailView`'s scroll, one codebase at a time, in its own collapsible section.
struct Finding: Identifiable, Hashable {
    /// Which lens produced this finding.
    enum Kind: String, CaseIterable, Identifiable, Hashable {
        case violation
        case deadCode
        case health

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .violation:
                "Quality Violation"
            case .deadCode:
                "Dead Code"
            case .health:
                "Parse Diagnostic"
            }
        }

        var systemImage: String {
            switch self {
            case .violation:
                "exclamationmark.triangle"
            case .deadCode:
                "trash"
            case .health:
                "stethoscope"
            }
        }
    }

    /// A finding's severity, used as the list's primary sort key (highest first). No lens in this
    /// data model carries an explicit severity field, so this is derived structurally (see
    /// `FindingsAggregator`) rather than trusted from the source data — kept a closed, ordered
    /// vocabulary shared across every lens rather than each lens inventing its own ranking.
    enum Severity: Int, Comparable, CaseIterable, Hashable {
        case info
        case warning
        case critical

        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }

        var label: String {
            switch self {
            case .info:
                "Info"
            case .warning:
                "Warning"
            case .critical:
                "Critical"
            }
        }

        /// A non-color signal alongside the row's tint (never encode meaning in color alone).
        var systemImage: String {
            switch self {
            case .info:
                "info.circle"
            case .warning:
                "exclamationmark.triangle"
            case .critical:
                "flame"
            }
        }
    }

    /// Stable across app launches for a given codebase state — used both as `Identifiable`'s `id`
    /// and, once suppressed, as the baseline's key. Not stable across a code edit that shifts
    /// the flagged line (the same limitation SwiftLint's own baseline file has).
    let id: String
    let kind: Kind
    let severity: Severity
    let codebaseID: UUID
    let codebaseName: String
    let title: String
    let message: String
    let location: SourceLocation?
    /// The element this finding is about — `nil` when nothing resolvable was found (e.g. a
    /// health-check parse diagnostic, which carries no type/method identity), in which case "View
    /// Source" is the row's only action.
    let reference: CodeElementReference?
    /// The finding's "recency" for the list's secondary sort key: the codebase's own last-indexed
    /// timestamp — the freshest signal available without git-blame authorship, which isn't built yet.
    let indexedAt: Date?
}
