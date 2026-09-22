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

    @ViewBuilder var findingsSections: some View {
        let delta = findingsDelta ?? CompareFindingsDelta(oldFindings: [], newFindings: [])
        let resolved = delta.resolved
        let added = delta.added
        findingsSummary(resolvedCount: resolved.count, addedCount: added.count, netChange: delta.netChange)
        DisclosureGroup(.app("View.CompareGitPanel.ResolvedFindings \(resolved.count)")) {
            findingRows(resolved)
        }
        .accessibilityIdentifier("delta.resolvedFindingsSection")
        DisclosureGroup(.app("View.CompareGitPanel.NewFindings \(added.count)")) {
            findingRows(added)
        }
        .accessibilityIdentifier("delta.findingsSection")
    }

    private func findingsSummary(resolvedCount: Int, addedCount: Int, netChange: Int) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(.app("View.CompareGitPanel.FindingsSummary \(resolvedCount) \(addedCount)"))
            Label {
                if netChange < 0 {
                    Text(.app("View.CompareGitPanel.NetFewer \(-netChange)"))
                } else if netChange > 0 {
                    Text(.app("View.CompareGitPanel.NetMore \(netChange)"))
                } else {
                    Text(.app("View.CompareGitPanel.NetUnchanged"))
                }
            } icon: {
                Image(systemName: netChangeSymbol(netChange))
            }
            .fontWeight(.semibold)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("delta.findingsSummary")
    }

    private func netChangeSymbol(_ netChange: Int) -> String {
        if netChange < 0 { return "arrow.down.circle" }
        if netChange > 0 { return "arrow.up.circle" }
        return "equal.circle"
    }

    private func findingRows(_ findings: [Finding]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(findings) { finding in
                findingDeltaRow(finding)
            }
        }
    }

    private func findingDeltaRow(_ finding: Finding) -> some View {
        let reviewed = model.isComparisonFindingReviewed(diagramID: diagram.id, findingID: finding.id)
        return HStack(alignment: .top, spacing: Spacing.xs) {
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
