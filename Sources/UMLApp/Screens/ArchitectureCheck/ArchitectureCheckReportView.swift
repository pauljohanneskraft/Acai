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
                violationRow(violation)
            }
        }
    }

    private func violationRow(_ violation: Violation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(violation.ruleKind)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.red.opacity(0.12))
                    .clipShape(Capsule())
                Text(violation.subject).font(.callout.bold())
            }
            Text(violation.message).font(.callout)
            if let source = violation.source {
                Text("\(source.filePath):\(source.line)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
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
