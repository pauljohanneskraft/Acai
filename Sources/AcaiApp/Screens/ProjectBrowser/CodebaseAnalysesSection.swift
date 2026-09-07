import SwiftUI
import AcaiQuality
import AcaiCore
import AcaiDiagram
import AcaiLibrary

/// Always evaluates — the configured `quality.yml` when one is set up, otherwise the built-in
/// curated smell budgets — so god classes, feature envy, low cohesion and the like surface out of
/// the box.
struct QualityCheckSection: View {
    let codebase: Codebase
    /// Still needed to seed the rules editor sheet.
    let artifact: CodeArtifact
    /// Precomputed in the background — always present (default budgets when no rules file is
    /// configured).
    let report: QualityReport
    let usesConfiguredRules: Bool
    let rulesError: String?

    @EnvironmentObject private var model: ProjectBrowserViewModel
    @State private var editing = false
    @State private var exportingCICheck = false

    private var configuration: QualityCheckConfiguration? {
        guard let config = codebase.qualityCheck, !config.rulesPath.isEmpty else { return nil }
        return config
    }

    var body: some View {
        let findings = report.violations.count
        let rules = report.checkedRuleCount
        CollapsibleSection(title: .app("View.QualityCheckSection.CodeQualityCheck")) {
            HStack(spacing: 8) {
                if !report.isPassing {
                    SectionCountBadge(
                        text: .app("View.QualityCheckSection.FindingsAcrossRules \(findings) \(rules)"),
                        tint: .orange)
                }
                Button(
                    configuration == nil
                        ? .app("View.QualityCheckSection.SetUp")
                        : .app("View.QualityCheckSection.Edit")
                ) { editing = true }
            }
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(localized: statusLine)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    // Kept out of the collapsible header (shared with the count badge and
                    // Set Up…/Edit…) so it doesn't crowd or truncate on iPhone-width layouts.
                    if configuration != nil {
                        Button(.app("View.QualityCheckSection.ExportCICheck")) { exportingCICheck = true }
                            .font(.caption)
                            .accessibilityIdentifier("qualityCheck.exportCICheckButton")
                    }
                }
                reportBody
            }
            .padding(.horizontal)
        }
        .sheet(isPresented: $editing) {
            QualityCheckEditorSheet(codebaseID: codebase.id, artifact: artifact)
                .environmentObject(model)
        }
        .sheet(isPresented: $exportingCICheck) {
            if let configuration {
                CIQualityCheckExportSheet(
                    codebaseName: codebase.name,
                    invocation: CIQualityCheckInvocation(
                        directoryPath: codebase.directoryPath,
                        rulesPath: configuration.rulesPath))
            }
        }
    }

    @ViewBuilder
    private var reportBody: some View {
        if let rulesError {
            QualityCheckPlaceholder(
                text: .app("View.QualityCheckSection.CouldNotLoadRulesBuiltIn \(rulesError)"),
                systemImage: "exclamationmark.triangle")
        }
        QualityCheckReportView(
            report: report, showsSummary: false, tint: .orange, codebase: codebase, artifact: artifact,
            onViewAsDiagram: viewAsCycleDiagram
        )
    }

    /// The Cycle Diagram entry point: a `cycle`-kind `Violation`'s `subject` is exactly
    /// `CycleFinder.Cycle.members.joined(separator: ",")` and `detail["scope"]` is the scope's raw
    /// value (see `QualityEvaluator.cycleViolations`) — enough to reconstruct a `CycleDiagramReference`
    /// with no re-detection needed. Creates the diagram pre-scoped and selects it directly.
    private func viewAsCycleDiagram(_ violation: Violation) {
        guard let projectID = model.projectID(for: codebase.id) else { return }
        let reference = CycleDiagramReference(
            scope: violation.detail["scope"] ?? CycleFinder.Scope.types.rawValue,
            members: violation.subject.split(separator: ",").map(String.init)
        )
        if let id = model.diagrams.add(to: projectID, codebaseID: codebase.id, content: .cycleDiagram(reference)) {
            model.selection = .generatedDiagram(id)
        }
    }

    private var statusLine: LocalizedStringResource {
        let rules = String(localized: .app("View.QualityCheckSection.Rules \(report.checkedRuleCount)"))
        guard usesConfiguredRules, let config = configuration else {
            return .app("View.QualityCheckSection.BuiltInBudgets \(rules)")
        }
        let origin = model.store.isManaged(path: config.rulesPath)
            ? String(localized: .app("View.QualityCheckSection.DefinedInApp"))
            : (config.rulesPath as NSString).abbreviatingWithTildeInPath
        return .app("View.QualityCheckSection.OriginRules \(origin) \(rules)")
    }
}

struct DeadCodeSection: View {
    let codebase: Codebase
    let artifact: CodeArtifact
    /// Precomputed in the background (see ``CodebaseAnalysis``).
    let report: DeadCodeScan.Report

    var body: some View {
        let coverage = Int((report.coverage.fraction * 100).rounded())
        CollapsibleSection(title: .app("View.DeadCodeSection.DeadCode")) {
            SectionCountBadge(
                text: report.candidates.isEmpty
                    ? .app("View.DeadCodeSection.NoneWithCoverage \(coverage)")
                    : .app("View.DeadCodeSection.CandidatesWithCoverage \(report.candidates.count) \(coverage)"),
                tint: report.candidates.isEmpty ? .secondary : .orange)
        } content: {
            DeadCodeReportView(report: report, artifact: artifact, codebase: codebase)
                .padding(.horizontal)
        }
    }
}

/// Kept unobtrusive on a clean codebase: collapsed by default, expanding only when there are
/// diagnostics.
struct ParseHealthSection: View {
    let codebase: Codebase
    /// Precomputed in the background (see ``CodebaseAnalysis``).
    let report: HealthCheck.Report

    var body: some View {
        let percent = Int((report.score * 100).rounded())
        CollapsibleSection(
            title: .app("View.ParseHealthSection.ParseHealth"),
            defaultExpanded: !report.diagnostics.isEmpty
        ) {
            SectionCountBadge(
                text: report.diagnostics.isEmpty
                    ? .app("View.ParseHealthSection.Score \(percent)")
                    : .app("View.ParseHealthSection.ScoreWithDiagnostics \(percent) \(report.diagnosticCount)"),
                tint: percent >= 90 ? .secondary : .red)
        } content: {
            HealthReportView(report: report, codebase: codebase)
                .padding(.horizontal)
        }
    }
}

struct SectionCountBadge: View {
    let text: LocalizedStringResource
    var tint: Color = .secondary

    var body: some View {
        Text(localized: text)
            .font(.caption)
            .foregroundStyle(tint)
    }
}
