import AcaiCore
import AcaiDiagram
import AcaiQuality
import Foundation

/// One flaw the Atlas's findings section lists. Deliberately plain text — the Atlas is an export
/// format, so its severity/kind wording stays English and stable rather than following the reader's
/// locale (the app's own `Finding` carries the localized, interactive form of the same lenses).
public struct AtlasFinding: Sendable {
    /// Derived structurally rather than carried by any lens, so one ordered vocabulary ranks all
    /// three (see ``AtlasFindings``).
    public enum Severity: Int, Comparable, CaseIterable, Sendable {
        case info
        case warning
        case critical

        public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }

        public var label: String {
            switch self {
            case .info:
                "Info"
            case .warning:
                "Warning"
            case .critical:
                "Critical"
            }
        }
    }

    public enum Kind: String, CaseIterable, Sendable {
        case violation
        case deadCode
        case health

        public var displayName: String {
            switch self {
            case .violation:
                "Quality Violation"
            case .deadCode:
                "Dead Code"
            case .health:
                "Parse Diagnostic"
            }
        }
    }

    public let kind: Kind
    public let severity: Severity
    public let title: String
    public let message: String
    public let location: SourceLocation?

    public init(
        kind: Kind, severity: Severity, title: String, message: String, location: SourceLocation?
    ) {
        self.kind = kind
        self.severity = severity
        self.title = title
        self.message = message
        self.location = location
    }

    /// The findings section's one-line form: severity, lens, subject, explanation and location.
    public var line: String {
        var line = "[\(severity.label)] \(kind.displayName) — \(title): \(message)"
        if let location {
            line += " (\(location.filePath):\(location.line))"
        }
        return line
    }
}

/// Normalizes the three whole-artifact quality lenses into the Atlas's findings section. A value you
/// instantiate over one codebase's reports and read `findings` from — the same normalization
/// whether the reports came from the app's cached analysis or from a headless `acai atlas` run, so
/// both produce the same document.
public struct AtlasFindings {
    public let quality: QualityReport
    public let deadCode: DeadCodeScan.Report
    public let health: HealthCheck.Report

    public init(quality: QualityReport, deadCode: DeadCodeScan.Report, health: HealthCheck.Report) {
        self.quality = quality
        self.deadCode = deadCode
        self.health = health
    }

    public var findings: [AtlasFinding] {
        violationFindings + deadCodeFindings + healthFindings
    }

    private var violationFindings: [AtlasFinding] {
        quality.violations.map { violation in
            AtlasFinding(
                kind: .violation,
                // A dependency cycle is a structural problem, not just a style nit — ranked above
                // an ordinary rule breach (e.g. a budget or naming-convention violation).
                severity: violation.ruleKind == "cycle" ? .critical : .warning,
                title: violation.subject,
                message: violation.message,
                location: violation.source)
        }
    }

    private var deadCodeFindings: [AtlasFinding] {
        let coverage = Int((deadCode.coverage.fraction * 100).rounded())
        return deadCode.candidates.map { candidate in
            AtlasFinding(
                kind: .deadCode,
                // A best-effort lead, not a verdict (see `DeadCodeScan`'s own doc comment on
                // `coverage`) — ranked below an actual rule breach or parse error.
                severity: .info,
                title: candidate.id,
                message: "No resolved caller found (call-graph coverage \(coverage)% — may be a false positive).",
                location: candidate.location)
        }
    }

    private var healthFindings: [AtlasFinding] {
        health.diagnostics.map { diagnostic in
            AtlasFinding(
                kind: .health,
                severity: diagnostic.kind == .error ? .critical : .warning,
                title: diagnostic.message,
                message: diagnostic.kind.rawValue,
                location: diagnostic.location)
        }
    }
}
