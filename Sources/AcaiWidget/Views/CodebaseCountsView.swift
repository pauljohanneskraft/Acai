import SwiftUI
import AcaiAppModel

/// How much the last analysis found. A count the app has not computed is left out rather than
/// shown as zero, which would read as "found nothing".
struct CodebaseCountsView: View {
    let snapshot: CodebaseWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: .spacingXXS) {
            if let typeCount = snapshot.typeCount {
                Text(.widget("View.CodebaseCountsView.Types \(typeCount)"))
            }
            if let findingCount = snapshot.findingCount {
                findings(findingCount)
            }
            if snapshot.hasParseErrors {
                Text(.widget("View.CodebaseCountsView.ParseErrors"))
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func findings(_ findingCount: Int) -> some View {
        if let criticalCount = snapshot.criticalFindingCount, criticalCount > 0 {
            Text(.widget("View.CodebaseCountsView.FindingsCritical \(findingCount) \(criticalCount)"))
        } else {
            Text(.widget("View.CodebaseCountsView.Findings \(findingCount)"))
        }
    }
}
