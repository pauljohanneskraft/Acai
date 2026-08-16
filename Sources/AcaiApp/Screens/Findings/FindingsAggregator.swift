import Foundation
import AcaiCore
import AcaiQuality
import AcaiDiagram

/// Aggregates the unified Findings list for one project: every quality violation, dead-code
/// candidate, and parse diagnostic across every codebase, normalized to `Finding`. Callers own
/// waiting for each codebase's analysis to load first (`ensureAnalysisLoaded`); a codebase whose
/// analysis isn't ready yet simply contributes nothing this call, rather than blocking.
///
/// `@MainActor` because it reads `ProjectBrowserViewModel`'s main-actor-isolated caches directly.
@MainActor
struct FindingsAggregator {
    let project: Project
    let model: ProjectBrowserViewModel

    /// Unsorted and unfiltered — `FindingsView` applies severity/recency ordering and the
    /// kind/codebase filters on top.
    func findings() -> [Finding] {
        project.codebases.flatMap(findings(for:))
    }

    /// Drives the view's partial "Analyzing N more codebase(s)…" note rather than a single
    /// all-or-nothing loading screen.
    func codebasesStillAnalyzing() -> [Codebase] {
        project.codebases.filter { codebase in
            model.artifact(for: codebase.id) != nil && model.analysis(for: codebase.id) == nil
        }
    }

    /// Never been indexed — not an error, but the view surfaces this explicitly rather than
    /// silently omitting them.
    func codebasesNotIndexed() -> [Codebase] {
        project.codebases.filter { model.artifact(for: $0.id) == nil }
    }

    func findings(for codebase: Codebase) -> [Finding] {
        guard let analysis = model.analysis(for: codebase.id) else { return [] }
        return findings(for: codebase, analysis: analysis, artifact: model.artifact(for: codebase.id))
    }

    /// Same mapping as `findings(for:)`, but against an explicit artifact/analysis pair instead of
    /// the live model's cache — for recomputing findings against a historical revision (the
    /// Compare panel's findings delta).
    func findings(for codebase: Codebase, analysis: CodebaseAnalysis, artifact: CodeArtifact?) -> [Finding] {
        var results: [Finding] = []
        results.append(contentsOf: violationFindings(analysis.quality, codebase: codebase, artifact: artifact))
        results.append(contentsOf: deadCodeFindings(analysis.deadCode, codebase: codebase, artifact: artifact))
        results.append(contentsOf: healthFindings(analysis.health, codebase: codebase))
        return results
    }

    private func violationFindings(
        _ report: QualityReport, codebase: Codebase, artifact: CodeArtifact?
    ) -> [Finding] {
        report.violations.enumerated().map { offset, violation in
            Finding(
                id: "violation-\(codebase.id)-\(violation.ruleKind)-\(violation.subject)-\(offset)",
                kind: .violation,
                // A dependency cycle is a structural problem, not just a style nit — ranked above
                // an ordinary rule breach (e.g. a budget or naming-convention violation).
                severity: violation.ruleKind == "cycle" ? .critical : .warning,
                codebaseID: codebase.id,
                codebaseName: codebase.name,
                title: violation.subject,
                message: violation.message,
                location: violation.source,
                reference: artifact.flatMap { violation.codeElementReference(in: $0) },
                indexedAt: codebase.lastIndexed)
        }
    }

    private func deadCodeFindings(
        _ report: DeadCodeScan.Report, codebase: Codebase, artifact: CodeArtifact?
    ) -> [Finding] {
        let coverage = Int((report.coverage.fraction * 100).rounded())
        return report.candidates.map { candidate in
            Finding(
                id: "deadCode-\(codebase.id)-\(candidate.id)",
                kind: .deadCode,
                // A best-effort lead, not a verdict (see `DeadCodeScan`'s own doc comment on
                // `coverage`) — ranked below an actual rule breach or parse error.
                severity: .info,
                codebaseID: codebase.id,
                codebaseName: codebase.name,
                title: candidate.id,
                message: "No resolved caller found (call-graph coverage \(coverage)% — may be a false positive).",
                location: candidate.location,
                reference: artifact.flatMap { candidate.codeElementReference(in: $0) },
                indexedAt: codebase.lastIndexed)
        }
    }

    private func healthFindings(_ report: HealthCheck.Report, codebase: Codebase) -> [Finding] {
        report.diagnostics.enumerated().map { offset, diagnostic in
            Finding(
                id: "health-\(codebase.id)-\(diagnostic.location.filePath)-\(diagnostic.location.line)-\(offset)",
                kind: .health,
                severity: diagnostic.kind == .error ? .critical : .warning,
                codebaseID: codebase.id,
                codebaseName: codebase.name,
                title: diagnostic.message,
                message: diagnostic.kind.rawValue,
                location: diagnostic.location,
                reference: nil,
                indexedAt: codebase.lastIndexed)
        }
    }
}
