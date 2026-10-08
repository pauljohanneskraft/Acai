import SwiftUI
import AcaiAppModel

/// A count the app hasn't computed is left out, since "0 findings" would claim it found nothing.
struct CodebaseCountsView: View {
    let snapshot: CodebaseWidgetSnapshot
    var showsAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: .spacingXXS) {
            if showsAll, let typeCount = snapshot.typeCount {
                Text(.widget("View.CodebaseCountsView.Types \(typeCount)"))
            }
            if let findingCount = snapshot.findingCount {
                findings(findingCount)
            }
            if showsAll, snapshot.hasParseErrors {
                Label {
                    Text(.widget("View.CodebaseCountsView.ParseErrors"))
                } icon: {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .minimumScaleFactor(0.8)
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
