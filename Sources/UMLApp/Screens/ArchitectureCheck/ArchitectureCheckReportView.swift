import SwiftUI
import UMLConformance
import UMLCore
import UMLLibrary

extension ConformanceRules {
    /// Evaluates these rules against `artifact`, using the artifact's own language configuration to
    /// resolve annotation stereotypes. The single evaluation entry point shared by the Architecture
    /// Check section (header count + report) and the editor's live preview.
    func report(for artifact: CodeArtifact) -> ConformanceReport {
        ConformanceEvaluator(
            rules: self,
            languageResolver: artifact.standardLanguageResolver
        ).evaluate(artifact)
    }
}

/// Renders the outcome of evaluating a set of conformance rules against an artifact: a pass banner or
/// the list of violations. Pure rendering — the report is computed by the caller (which also surfaces
/// the violation count in its header) and injected, so both the codebase's Architecture Check section
/// and the editor's live preview share it without re-evaluating.
struct ArchitectureCheckReportView: View {
    let report: ConformanceReport
    /// Whether to show the leading "N violation(s) across N rule(s)" summary. The codebase section
    /// carries that string in its collapsible header instead, so it opts out; the editor keeps it.
    var showsSummary: Bool = true

    var body: some View {
        if report.isPassing {
            ArchitectureCheckPlaceholder(
                text: report.checkedRuleCount == 0
                    ? "No rules defined yet — add at least one rule to check this codebase."
                    : "Conformance OK — \(report.checkedRuleCount) rule(s) checked, no violations.",
                systemImage: report.checkedRuleCount == 0 ? "doc.text.magnifyingglass" : "checkmark.seal")
        } else {
            violationList(report)
        }
    }

    private func violationList(_ report: ConformanceReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsSummary {
                Text("\(report.violations.count) violation(s) across \(report.checkedRuleCount) rule(s)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.red)
            }
            ForEach(Array(report.violations.enumerated()), id: \.offset) { _, violation in
                ViolationRowView(violation: violation)
            }
        }
    }
}

/// Shared empty/status placeholder for the architecture-check surfaces.
struct ArchitectureCheckPlaceholder: View {
    let text: String
    var systemImage: String = "doc.text.magnifyingglass"

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage).font(.system(size: 28)).foregroundStyle(.secondary)
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}
