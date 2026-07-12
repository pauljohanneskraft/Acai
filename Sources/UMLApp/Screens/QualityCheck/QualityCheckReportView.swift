import SwiftUI
import UMLQuality
import UMLCore
import UMLLibrary

extension QualityRules {
    /// Evaluates these rules against `artifact`, using the artifact's own language configuration to
    /// resolve annotation stereotypes. The single evaluation entry point shared by the Code Quality
    /// Check section (header count + report) and the editor's live preview.
    func report(for artifact: CodeArtifact) -> QualityReport {
        QualityEvaluator(
            rules: self,
            languageResolver: artifact.standardLanguageResolver
        ).evaluate(artifact)
    }
}

/// Renders the outcome of evaluating a set of quality rules against an artifact: a pass banner or
/// the list of violations. Pure rendering — the report is computed by the caller (which also surfaces
/// the violation count in its header) and injected, so both the codebase's Code Quality Check section
/// and the editor's live preview share it without re-evaluating.
struct QualityCheckReportView: View {
    let report: QualityReport
    /// Whether to show the leading "N finding(s) across N rule(s)" summary. The codebase section
    /// carries that string in its collapsible header instead, so it opts out; the editor keeps it.
    var showsSummary: Bool = true
    /// The row/summary accent. Red for the gate preview in the editor; orange for the advisory
    /// findings shown in the codebase Code Quality Check section.
    var tint: Color = .red
    /// Lets each violation row reveal its file in Finder. `nil` in the rules editor's live preview,
    /// which has no codebase directory to resolve a relative path against.
    var codebase: Codebase?

    var body: some View {
        if report.isPassing {
            QualityCheckPlaceholder(
                text: report.checkedRuleCount == 0
                    ? "No rules defined yet — add at least one rule to check this codebase."
                    : "Quality OK — \(report.checkedRuleCount) rule(s) checked, no violations.",
                systemImage: report.checkedRuleCount == 0 ? "doc.text.magnifyingglass" : "checkmark.seal")
        } else {
            violationList(report)
        }
    }

    private func violationList(_ report: QualityReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsSummary {
                Text("\(report.violations.count) finding(s) across \(report.checkedRuleCount) rule(s)")
                    .font(.subheadline.bold())
                    .foregroundStyle(tint)
            }
            ForEach(Array(report.violations.prefix(analysisReportLimit).enumerated()), id: \.offset) { _, violation in
                ViolationRowView(violation: violation, tint: tint, codebase: codebase)
            }
        }
    }
}

/// Shared empty/status placeholder for the quality-check surfaces.
struct QualityCheckPlaceholder: View {
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
