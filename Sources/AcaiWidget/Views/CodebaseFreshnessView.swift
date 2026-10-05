import SwiftUI
import AcaiAppModel

/// When the codebase was analysed, and whether it had drifted since — as a label beside its icon,
/// never a bare colour, so the state survives being read aloud or seen without colour.
struct CodebaseFreshnessView: View {
    let snapshot: CodebaseWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: .spacingXXS) {
            if let analysedAt = snapshot.analysedAt {
                HStack(spacing: .spacingXXS) {
                    Text(.widget("View.CodebaseFreshnessView.Analysed"))
                    // A date the system formats and keeps current, rather than one spelled by hand.
                    Text(analysedAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            statusLabel
            if let revision = snapshot.analysedRevision {
                // A revision is content: it is what the repository calls that commit.
                Text(verbatim: revision)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        if snapshot.freshnessCheckedAt == nil {
            // Never compared against the code, so claiming either freshness or drift would be a guess.
            label(.widget("View.CodebaseFreshnessView.NotChecked"), "questionmark.circle.fill", .secondary)
        } else if snapshot.isOutOfDate {
            label(.widget("View.CodebaseFreshnessView.OutOfDate"), "exclamationmark.triangle.fill", .orange)
        } else {
            label(.widget("View.CodebaseFreshnessView.UpToDate"), "checkmark.circle.fill", .green)
        }
    }

    private func label(
        _ text: LocalizedStringResource, _ systemImage: String, _ tint: Color
    ) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(tint)
        }
        .font(.caption.weight(.medium))
        .labelStyle(.titleAndIcon)
    }
}
