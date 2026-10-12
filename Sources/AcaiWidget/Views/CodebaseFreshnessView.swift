import SwiftUI
import AcaiAppModel

/// Whether the code had changed since the analysis, always as a label beside the icon, never colour alone.
struct CodebaseStatusLabel: View {
    let snapshot: CodebaseWidgetSnapshot

    var body: some View {
        if snapshot.freshnessCheckedAt == nil {
            label(.widget("View.CodebaseFreshnessView.NotChecked"), "questionmark.circle.fill", .secondary)
        } else if snapshot.isOutOfDate {
            label(.widget("View.CodebaseFreshnessView.OutOfDate"), "exclamationmark.triangle.fill", .orange)
        } else {
            label(.widget("View.CodebaseFreshnessView.UpToDate"), "checkmark.circle.fill", .green)
        }
    }

    private func label(_ text: LocalizedStringResource, _ systemImage: String, _ tint: Color) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(tint)
        }
        .font(.caption.weight(.medium))
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
}

/// When the analysis and the last freshness check ran, as ages that stay current between timeline reloads.
struct CodebaseFreshnessView: View {
    let snapshot: CodebaseWidgetSnapshot
    var showsCheckAndRevision = false

    var body: some View {
        VStack(alignment: .leading, spacing: .spacingXXS) {
            if let analysedAt = snapshot.analysedAt.map(RelativeDate.init) {
                Text(widget: "View.CodebaseFreshnessView.Analysed \(analysedAt.text)")
            }
            if showsCheckAndRevision {
                if let checkedAt = snapshot.freshnessCheckedAt.map(RelativeDate.init) {
                    Text(widget: "View.CodebaseFreshnessView.Checked \(checkedAt.text)")
                }
                if let revision = snapshot.analysedRevision {
                    Text(verbatim: revision)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

struct RelativeDate {
    let date: Date

    /// "2 hours ago", kept current by the system rather than frozen at the entry's date.
    var text: Text {
        if #available(iOS 18, *) {
            Text(.currentDate, format: .reference(to: date, maxFieldCount: 1))
        } else {
            Text(date, style: .relative)
        }
    }
}
