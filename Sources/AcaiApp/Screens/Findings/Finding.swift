import Foundation
import AcaiCore
import AcaiRender

/// One row in the project-level Findings view — a quality violation, a dead-code candidate,
/// or a health-check parse diagnostic, normalized to one shape so every flaw-detection lens the
/// engine produces can be sorted, filtered, and resolved through `CodeElementReference`
/// identically, regardless of which scan produced it.
struct Finding: Identifiable, Hashable {
    enum Kind: String, CaseIterable, Identifiable, Hashable {
        case violation
        case deadCode
        case health

        var id: String { rawValue }

        var title: LocalizedStringResource {
            switch self {
            case .violation:
                .app("Finding.Kind.QualityViolation")
            case .deadCode:
                .app("Finding.Kind.DeadCode")
            case .health:
                .app("Finding.Kind.ParseDiagnostic")
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

    /// The list's primary sort key (highest first), derived by the shared `AtlasFinding`.
    enum Severity: Int, Comparable, CaseIterable, Hashable {
        case info
        case warning
        case critical

        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }

        var title: LocalizedStringResource {
            switch self {
            case .info:
                .app("Finding.Severity.Info")
            case .warning:
                .app("Finding.Severity.Warning")
            case .critical:
                .app("Finding.Severity.Critical")
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

    /// Derived from the finding's own identity, never from its position in a report, so it is the
    /// same across launches and reindexes — used both as `Identifiable`'s `id` and, once suppressed,
    /// as the baseline's key. Not stable across a code edit that shifts the flagged line (the same
    /// limitation SwiftLint's own baseline file has).
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
    /// The list's secondary sort key: the codebase's own last-indexed timestamp, the freshest
    /// recency signal available without git-blame authorship.
    let indexedAt: Date?
    /// Present only for a `cycle`-kind violation finding — lets `FindingRow` offer the same "open
    /// as diagram" action `ViolationRowView` gives a cycle violation in the Quality Check section,
    /// without needing to re-parse `title`/`message`. `nil` for every other finding. No default
    /// value here: a stored `let` with an inline default is dropped from the synthesized
    /// memberwise initializer entirely, so every call site passes it explicitly instead.
    let cycle: CycleReference?
}

extension Finding {
    /// A `cycle`-kind finding's scope and members. `scope` stays a plain
    /// `AcaiQuality.CycleFinder.Scope.rawValue` string rather than the enum itself, mirroring how
    /// `QualityEvaluator.cycleViolations` already encodes it into `Violation.detail["scope"]` — no
    /// extra dependency on `AcaiQuality`'s types needed here.
    struct CycleReference: Hashable {
        let scope: String
        let members: [String]
    }

    init(_ finding: AtlasFinding, codebase: Codebase, reference: CodeElementReference?, cycle: CycleReference?) {
        self.init(
            id: "\(finding.kind.rawValue)-\(codebase.id)-\(finding.identity)",
            kind: Kind(finding.kind),
            severity: Severity(finding.severity),
            codebaseID: codebase.id,
            codebaseName: codebase.name,
            title: finding.title,
            message: finding.message,
            location: finding.location,
            reference: reference,
            indexedAt: codebase.lastIndexed,
            cycle: cycle)
    }
}

extension Finding.Kind {
    init(_ kind: AtlasFinding.Kind) {
        switch kind {
        case .violation:
            self = .violation
        case .deadCode:
            self = .deadCode
        case .health:
            self = .health
        }
    }
}

extension Finding.Severity {
    init(_ severity: AtlasFinding.Severity) {
        switch severity {
        case .info:
            self = .info
        case .warning:
            self = .warning
        case .critical:
            self = .critical
        }
    }
}
