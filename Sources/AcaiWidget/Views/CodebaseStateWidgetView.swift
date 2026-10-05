import SwiftUI
import WidgetKit
import AcaiAppModel

struct CodebaseStateWidgetView: View {
    let entry: CodebaseStateEntry

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
            CodebaseAnalysedView(snapshot: snapshot)
        }
    }
}

/// The empty and error states: a widget cannot show a retry button, so each says which action in
/// the app resolves it rather than only that something is absent.
struct CodebaseStateUnavailableView: View {
    let message: LocalizedStringResource
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: .spacingXXS) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct CodebaseNotAnalysedView: View {
    let snapshot: CodebaseWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: .spacingXXS) {
            CodebaseNameView(name: snapshot.codebaseName)
            Text(.widget("View.CodebaseStateWidgetView.NotAnalysed"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(.widget("View.CodebaseStateWidgetView.AnalyseInApp"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

struct CodebaseAnalysedView: View {
    let snapshot: CodebaseWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: .spacingS) {
            CodebaseNameView(name: snapshot.codebaseName)
            CodebaseFreshnessView(snapshot: snapshot)
            CodebaseCountsView(snapshot: snapshot)
            Spacer(minLength: 0)
            // The whole point of the footnote: a widget that showed these numbers without it would
            // read as live state, which it never is.
            Text(.widget("View.CodebaseStateWidgetView.AsOfLastAnalysis"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

struct CodebaseNameView: View {
    let name: String

    var body: some View {
        // A codebase's name is content, never translated.
        Text(verbatim: name)
            .font(.headline)
            .lineLimit(2)
    }
}
