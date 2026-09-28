import AcaiCore
import AcaiDiagram
import AcaiQuality
import Foundation

/// One flaw the Atlas's findings section lists, in stable English rather than the reader's locale.
public struct AtlasFinding: Sendable {
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

    public var line: String {
        var line = "[\(severity.label)] \(kind.displayName) — \(title): \(message)"
        if let location {
            line += " (\(location.filePath):\(location.line))"
        }
        return line
    }
}

extension AtlasFinding {
    public init(violation: Violation) {
        self.init(
            kind: .violation,
            // A dependency cycle is a structural problem, ranked above an ordinary rule breach.
            severity: violation.ruleKind == "cycle" ? .critical : .warning,
            title: violation.subject,
            message: violation.message,
            location: violation.source)
    }

    /// Ranked `.info`: a best-effort lead whose reliability is bounded by the call graph's `coverage`.
    public init(deadCode candidate: DeadCodeScan.Candidate, coverage: CallGraph.Coverage) {
        let percent = Int((coverage.fraction * 100).rounded())
        self.init(
            kind: .deadCode,
            severity: .info,
            title: candidate.id,
            message: "No resolved caller found (call-graph coverage \(percent)% — may be a false positive).",
            location: candidate.location)
    }

    public init(diagnostic: ParseDiagnostic) {
        self.init(
            kind: .health,
            severity: diagnostic.kind == .error ? .critical : .warning,
            title: diagnostic.message,
            message: diagnostic.kind.rawValue,
            location: diagnostic.location)
    }
}

/// The Atlas's findings section over one codebase's three quality lenses, in lens order.
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
        quality.violations.map(AtlasFinding.init(violation:))
            + deadCode.candidates.map { AtlasFinding(deadCode: $0, coverage: deadCode.coverage) }
            + health.diagnostics.map(AtlasFinding.init(diagnostic:))
    }
}
