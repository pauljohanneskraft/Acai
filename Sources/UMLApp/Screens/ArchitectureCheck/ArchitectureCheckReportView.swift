import SwiftUI
import UMLConformance
import UMLCore

/// Renders the outcome of evaluating a set of conformance `rules` against an artifact: a pass banner
/// or the list of violations. Pure rendering — it recomputes the report from its inputs, so both the
/// codebase's Analyses section and the editor's live preview can share it.
struct ArchitectureCheckReportView: View {
    let rules: ConformanceRules
    let artifact: CodeArtifact

    private var report: ConformanceReport {
        ConformanceEvaluator(
            rules: rules,
            annotationStereotypes: artifact.standardLanguageConfiguration.annotationStereotypes
        ).evaluate(artifact)
    }

    var body: some View {
        let report = report
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
            Text("\(report.violations.count) violation(s) across \(report.checkedRuleCount) rule(s)")
                .font(.subheadline.bold())
                .foregroundStyle(.red)
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
