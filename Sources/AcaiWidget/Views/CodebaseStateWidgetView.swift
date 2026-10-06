import SwiftUI
import WidgetKit
import AcaiAppModel

struct CodebaseStateWidgetView: View {
    let entry: CodebaseStateEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .combine)
            .widgetURL(entry.state.snapshot?.address.url)
    }

    @ViewBuilder
    private var content: some View {
        switch entry.state {
        case .nothingShared:
            CodebaseStateUnavailableView(
                message: .widget("View.CodebaseStateWidgetView.NothingShared"),
                systemImage: "square.stack.3d.up.slash")
        case .codebaseMissing:
            CodebaseStateUnavailableView(
                message: .widget("View.CodebaseStateWidgetView.CodebaseMissing"),
                systemImage: "questionmark.folder")
        case .notAnalysed(let snapshot):
            CodebaseNotAnalysedView(snapshot: snapshot)
        case .analysed(let snapshot):
            CodebaseAnalysedView(snapshot: snapshot, isCompact: family == .systemSmall)
        }
    }
}

/// A widget has no retry button, so each empty state names the action in the app that resolves it.
struct CodebaseStateUnavailableView: View {
    let message: LocalizedStringResource
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: .spacingXS) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .minimumScaleFactor(0.8)
        }
    }
}

struct CodebaseNotAnalysedView: View {
    let snapshot: CodebaseWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: .spacingXS) {
            CodebaseNameView(name: snapshot.codebaseName)
            Text(.widget("View.CodebaseStateWidgetView.NotAnalysed"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(.widget("View.CodebaseStateWidgetView.AnalyseInApp"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)
        }
    }
}

struct CodebaseAnalysedView: View {
    let snapshot: CodebaseWidgetSnapshot
    let isCompact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: .spacingXS) {
            if isCompact {
                CodebaseNameView(name: snapshot.codebaseName)
                CodebaseStatusLabel(snapshot: snapshot)
                CodebaseFreshnessView(snapshot: snapshot)
                CodebaseCountsView(snapshot: snapshot)
            } else {
                HStack(alignment: .top, spacing: .spacingM) {
                    VStack(alignment: .leading, spacing: .spacingXS) {
                        CodebaseNameView(name: snapshot.codebaseName)
                        CodebaseStatusLabel(snapshot: snapshot)
                        CodebaseFreshnessView(snapshot: snapshot, showsCheckAndRevision: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    CodebaseCountsView(snapshot: snapshot, showsAll: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
            // Without it the numbers would read as live state, which the widget never has.
            Text(.widget("View.CodebaseStateWidgetView.AsOfLastAnalysis"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .layoutPriority(1)
        }
    }
}

struct CodebaseNameView: View {
    let name: String

    var body: some View {
        Text(verbatim: name)
            .font(.headline)
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
    }
}
