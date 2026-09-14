import SwiftUI

extension CompareGitPanel {
    private var findingsDelta: CompareFindingsDelta? {
        guard let codebase = model.codebase(for: diagram.codebaseID),
              let projectID = model.projectID(for: codebase.id),
              let project = model.store.projects.first(where: { $0.id == projectID }),
              let comparisonAnalysis = model.comparisonAnalysis(for: diagram)
        else { return nil }
        let aggregator = FindingsAggregator(project: project, model: model)
        let oldFindings = aggregator.findings(
            for: codebase, analysis: comparisonAnalysis, artifact: model.comparisonSemanticArtifact(for: diagram))
        let liveFindings = aggregator.findings(for: codebase)
        return CompareFindingsDelta(oldFindings: oldFindings, newFindings: liveFindings)
    }

    private var newFindings: [Finding] { findingsDelta?.added ?? [] }

    private var resolvedFindings: [Finding] { findingsDelta?.resolved ?? [] }

    var findingsDeltaSection: some View {
        DisclosureGroup(.app("View.CompareGitPanel.NewFindings \(newFindings.count)")) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(newFindings) { finding in
                    findingDeltaRow(finding)
                }
            }
        }
        .accessibilityIdentifier("delta.findingsSection")
    }

    var resolvedFindingsSection: some View {
        DisclosureGroup(.app("View.CompareGitPanel.ResolvedFindings \(resolvedFindings.count)")) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(resolvedFindings) { finding in
                    findingDeltaRow(finding)
                }
            }
        }
        .accessibilityIdentifier("delta.resolvedFindingsSection")
    }

    private func findingDeltaRow(_ finding: Finding) -> some View {
        let reviewed = model.isComparisonFindingReviewed(diagramID: diagram.id, findingID: finding.id)
        return HStack(alignment: .top, spacing: 6) {
            Button {
                model.toggleComparisonFindingReviewed(diagramID: diagram.id, findingID: finding.id)
            } label: {
                Image(systemName: reviewed ? "checkmark.square.fill" : "square")
                    .foregroundStyle(reviewed ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(reviewed
                ? .app("View.CompareGitOverlay.MarkNotReviewed")
                : .app("View.CompareGitOverlay.MarkReviewed"))
            .accessibilityIdentifier("delta.finding.reviewToggle.\(finding.id)")

            FindingRow(finding: finding, codebase: model.codebase(for: diagram.codebaseID))
        }
    }
}
