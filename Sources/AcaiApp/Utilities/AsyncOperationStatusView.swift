import SwiftUI

/// The `.loading`/`.loaded`/`.error` accessibility identifier suffixes let a UI test wait on a real
/// completion signal instead of inferring "done" from an unrelated downstream element.
enum AsyncOperationPhase: Equatable {
    case idle
    case loading(LocalizedStringResource)
    case loaded
    case failed(String)

    var isInFlight: Bool {
        if case .loading = self { return true }
        return false
    }
}

struct AsyncOperationStatusView: View {
    let identifierPrefix: String
    let phase: AsyncOperationPhase

    var body: some View {
        switch phase {
        case .idle:
            EmptyView()
        case .loading(let title):
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(localized: title).font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("\(identifierPrefix).loading")
        case .loaded:
            Text(.app("View.AsyncOperationStatusView.Loaded")).font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("\(identifierPrefix).loaded")
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
                .accessibilityIdentifier("\(identifierPrefix).error")
        }
    }
}
