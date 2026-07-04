import SwiftUI
import UMLConformance
import UMLCore
import UMLDiagram
import UMLLibrary

/// The architecture-conformance check as its own collapsible section. An analysis produces a report,
/// not a canvas, so it lives here rather than among the diagrams. Shows the check's status and its
/// violations inline, and opens the rules editor from the header.
struct ArchitectureCheckSection: View {
    let codebase: Codebase
    /// Still needed to seed the rules editor sheet.
    let artifact: CodeArtifact
    /// The conformance report, precomputed in the background — `nil` when no check is configured or its
    /// rules failed to load (see `rulesError`).
    let report: ConformanceReport?
    /// The rules-load failure message, when a check is configured but its file couldn't be read.
    let rulesError: String?

    @EnvironmentObject private var model: ProjectBrowserViewModel
    @State private var editing = false

    private var configuration: ArchitectureCheckConfiguration? {
        guard let config = codebase.architectureCheck, !config.rulesPath.isEmpty else { return nil }
        return config
    }

    var body: some View {
        CollapsibleSection(title: "Architecture Check") {
            HStack(spacing: 8) {
                if let report, !report.isPassing {
                    SectionCountBadge(text: "\(report.violations.count) violation(s)", tint: .red)
                }
                Button(configuration == nil ? "Set Up…" : "Edit…") { editing = true }
            }
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                Text(statusLine)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                if configuration != nil {
                    reportBody
                }
            }
            .padding(.horizontal)
        }
        .sheet(isPresented: $editing) {
            ArchitectureCheckEditorSheet(codebaseID: codebase.id, artifact: artifact)
                .environmentObject(model)
        }
    }

    @ViewBuilder
    private var reportBody: some View {
        if let rulesError {
            ArchitectureCheckPlaceholder(
                text: "Could not load rules: \(rulesError)",
                systemImage: "exclamationmark.triangle")
        } else if let report {
            ArchitectureCheckReportView(report: report)
        }
    }

    private var statusLine: String {
        guard let config = configuration else { return "No check configured yet." }
        let origin = model.store.isManaged(path: config.rulesPath)
            ? "Defined in app"
            : (config.rulesPath as NSString).abbreviatingWithTildeInPath
        if let report {
            return "\(origin) · \(report.checkedRuleCount) rule(s)"
        }
        return origin
    }
}

/// Ranked code smells as their own collapsible section. The scan runs once here: its count is shown
/// in the header and the findings are handed to the report view.
struct CodeSmellsSection: View {
    /// Precomputed in the background (see ``CodebaseAnalysis``).
    let findings: [Violation]

    var body: some View {
        CollapsibleSection(title: "Code Smells") {
            SectionCountBadge(
                text: findings.isEmpty ? "none" : "\(findings.count) smell(s)",
                tint: findings.isEmpty ? .secondary : .orange)
        } content: {
            SmellsReportView(findings: findings)
                .padding(.horizontal)
        }
    }
}

/// Dead-code candidates as their own collapsible section. The scan runs once here: its candidate
/// count and call-graph coverage are shown in the header and the report is handed to the report view.
struct DeadCodeSection: View {
    /// Precomputed in the background (see ``CodebaseAnalysis``).
    let report: DeadCodeScan.Report

    var body: some View {
        let coverage = Int((report.coverage.fraction * 100).rounded())
        CollapsibleSection(title: "Dead Code") {
            SectionCountBadge(
                text: report.candidates.isEmpty
                    ? "none · \(coverage)% coverage"
                    : "\(report.candidates.count) · \(coverage)% coverage",
                tint: report.candidates.isEmpty ? .secondary : .orange)
        } content: {
            DeadCodeReportView(report: report)
                .padding(.horizontal)
        }
    }
}

/// Parse health as its own collapsible section. Kept unobtrusive on a clean codebase: collapsed by
/// default with a compact score in the header, expanding only when there are diagnostics. The check
/// runs once here and the report is handed to the report view.
struct ParseHealthSection: View {
    /// Precomputed in the background (see ``CodebaseAnalysis``).
    let report: HealthCheck.Report

    var body: some View {
        let percent = Int((report.score * 100).rounded())
        CollapsibleSection(
            title: "Parse Health",
            defaultExpanded: !report.diagnostics.isEmpty
        ) {
            SectionCountBadge(
                text: "health \(percent)%",
                tint: percent >= 90 ? .secondary : .red)
        } content: {
            HealthReportView(report: report)
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
