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
    let artifact: CodeArtifact

    @EnvironmentObject private var model: ProjectBrowserViewModel
    @State private var editing = false

    private var configuration: ArchitectureCheckConfiguration? {
        guard let config = codebase.architectureCheck, !config.rulesPath.isEmpty else { return nil }
        return config
    }

    var body: some View {
        // Load and evaluate once per render: the rules feed the status line, and the report feeds both
        // the header's violation count and the inline report.
        let rules = resolvedRules
        let report: ConformanceReport? = {
            guard case .success(let rules) = rules else { return nil }
            return rules.report(for: artifact)
        }()
        CollapsibleSection(title: "Architecture Check") {
            HStack(spacing: 8) {
                if let report, !report.isPassing {
                    SectionCountBadge(text: "\(report.violations.count) violation(s)", tint: .red)
                }
                Button(configuration == nil ? "Set Up…" : "Edit…") { editing = true }
            }
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                Text(statusLine(for: rules))
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                if configuration != nil {
                    reportBody(rules: rules, report: report)
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
    private func reportBody(rules: Result<ConformanceRules, Error>?, report: ConformanceReport?) -> some View {
        switch rules {
        case .none:
            EmptyView()
        case .success:
            if let report {
                ArchitectureCheckReportView(report: report)
            }
        case .failure(let error):
            ArchitectureCheckPlaceholder(
                text: "Could not load rules: \(error.localizedDescription)",
                systemImage: "exclamationmark.triangle")
        }
    }

    /// `nil` when no check is configured, otherwise the decoded rules or the load error.
    private var resolvedRules: Result<ConformanceRules, Error>? {
        configuration.map { config in Result { try config.loadRules() } }
    }

    private func statusLine(for rules: Result<ConformanceRules, Error>?) -> String {
        guard let config = configuration else { return "No check configured yet." }
        let origin = model.store.isManaged(path: config.rulesPath)
            ? "Defined in app"
            : (config.rulesPath as NSString).abbreviatingWithTildeInPath
        switch rules {
        case .success(let rules):
            return "\(origin) · \(rules.ruleCount) rule(s)"
        default:
            return origin
        }
    }
}

/// Ranked code smells as their own collapsible section. The scan runs once here: its count is shown
/// in the header and the findings are handed to the report view.
struct CodeSmellsSection: View {
    let artifact: CodeArtifact

    private var findings: [Violation] {
        SmellScan(
            artifact: artifact,
            annotationStereotypes: artifact.standardLanguageConfiguration.annotationStereotypes
        ).findings
    }

    var body: some View {
        let findings = findings
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
    let artifact: CodeArtifact

    private var report: DeadCodeScan.Report {
        DeadCodeScan(
            artifact: artifact,
            entryPoints: artifact.standardLanguageConfiguration.entryPointMarkers
        ).report
    }

    var body: some View {
        let report = report
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
    let artifact: CodeArtifact

    private var report: HealthCheck.Report { HealthCheck(artifact: artifact).report }

    var body: some View {
        let report = report
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
