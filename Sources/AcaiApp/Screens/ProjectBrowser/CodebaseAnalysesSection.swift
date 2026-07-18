import SwiftUI
import AcaiQuality
import AcaiCore
import AcaiDiagram
import AcaiLibrary

/// The code-quality check as its own collapsible section. An analysis produces a report, not a
/// canvas, so it lives here rather than among the diagrams. It always evaluates — the configured
/// `quality.yml` when one is set up, otherwise the built-in curated smell budgets — so god classes,
/// feature envy, low cohesion and the like surface out of the box. Opens the rules editor from the
/// header to attach or tighten a custom rules file.
struct QualityCheckSection: View {
    let codebase: Codebase
    /// Still needed to seed the rules editor sheet.
    let artifact: CodeArtifact
    /// The quality report, precomputed in the background — always present (default budgets when no
    /// rules file is configured).
    let report: QualityReport
    /// Whether `report` came from a configured rules file (vs the built-in default smell budgets).
    let usesConfiguredRules: Bool
    /// The rules-load failure message, when a check is configured but its file couldn't be read.
    let rulesError: String?

    @EnvironmentObject private var model: ProjectBrowserViewModel
    @State private var editing = false

    private var configuration: QualityCheckConfiguration? {
        guard let config = codebase.qualityCheck, !config.rulesPath.isEmpty else { return nil }
        return config
    }

    var body: some View {
        CollapsibleSection(title: "Code Quality Check") {
            HStack(spacing: 8) {
                if !report.isPassing {
                    SectionCountBadge(
                        text: "\(report.violations.count) finding(s) across \(report.checkedRuleCount) rule(s)",
                        tint: .orange)
                }
                Button(configuration == nil ? "Set Up…" : "Edit…") { editing = true }
            }
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                Text(statusLine)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                reportBody
            }
            .padding(.horizontal)
        }
        .sheet(isPresented: $editing) {
            QualityCheckEditorSheet(codebaseID: codebase.id, artifact: artifact)
                .environmentObject(model)
        }
    }

    @ViewBuilder
    private var reportBody: some View {
        if let rulesError {
            QualityCheckPlaceholder(
                text: "Could not load rules: \(rulesError) — showing the built-in smell budgets instead.",
                systemImage: "exclamationmark.triangle")
        }
        QualityCheckReportView(report: report, showsSummary: false, tint: .orange, codebase: codebase)
    }

    private var statusLine: String {
        guard usesConfiguredRules, let config = configuration else {
            return "Built-in smell budgets · \(report.checkedRuleCount) rule(s)"
        }
        let origin = model.store.isManaged(path: config.rulesPath)
            ? "Defined in app"
            : (config.rulesPath as NSString).abbreviatingWithTildeInPath
        return "\(origin) · \(report.checkedRuleCount) rule(s)"
    }
}

/// Dead-code candidates as their own collapsible section. The scan runs once here: its candidate
/// count and call-graph coverage are shown in the header and the report is handed to the report view.
struct DeadCodeSection: View {
    let codebase: Codebase
    /// Precomputed in the background (see ``CodebaseAnalysis``).
    let report: DeadCodeScan.Report

    var body: some View {
        let coverage = Int((report.coverage.fraction * 100).rounded())
        CollapsibleSection(title: "Dead Code") {
            SectionCountBadge(
                text: report.candidates.isEmpty
                    ? "none · call-graph coverage \(coverage)%"
                    : "\(report.candidates.count) candidate(s) · call-graph coverage \(coverage)%",
                tint: report.candidates.isEmpty ? .secondary : .orange)
        } content: {
            DeadCodeReportView(report: report, codebase: codebase)
                .padding(.horizontal)
        }
    }
}

/// Parse health as its own collapsible section. Kept unobtrusive on a clean codebase: collapsed by
/// default with a compact score in the header, expanding only when there are diagnostics. The check
/// runs once here and the report is handed to the report view.
struct ParseHealthSection: View {
    let codebase: Codebase
    /// Precomputed in the background (see ``CodebaseAnalysis``).
    let report: HealthCheck.Report

    var body: some View {
        let percent = Int((report.score * 100).rounded())
        CollapsibleSection(
            title: "Parse Health",
            defaultExpanded: !report.diagnostics.isEmpty
        ) {
            SectionCountBadge(
                text: report.diagnostics.isEmpty
                    ? "\(percent)%"
                    : "\(percent)% · \(report.diagnosticCount) diagnostic(s)",
                tint: percent >= 90 ? .secondary : .red)
        } content: {
            HealthReportView(report: report, codebase: codebase)
                .padding(.horizontal)
        }
    }
}

/// A compact caption shown at the trailing edge of a collapsible section header, summarizing the
/// section's contents (a count or score) so it reads at a glance even when collapsed.
struct SectionCountBadge: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(tint)
    }
}
