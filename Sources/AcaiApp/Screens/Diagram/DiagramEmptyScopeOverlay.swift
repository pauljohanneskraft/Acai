import SwiftUI

enum DiagramEmptyReason: String, Sendable {
    case codebase
    case scope
    case filter
    case scopeAndFilter
}

struct DiagramEmptyScopeOverlay<NothingOfThisKind: View>: View {
    let reason: DiagramEmptyReason
    @ViewBuilder let nothingOfThisKind: () -> NothingOfThisKind
    let onUndo: () -> Void

    var body: some View {
        Group {
            switch reason {
            case .codebase:
                nothingOfThisKind()
            case .scope:
                undoable(
                    title: .app("View.DiagramEmptyScopeOverlay.NothingMatchesThisScope"),
                    detail: .app("View.DiagramEmptyScopeOverlay.ScopeHidEverything"),
                    systemImage: "scope",
                    undoTitle: .app("View.DiagramEmptyScopeOverlay.ResetScope"),
                    undoSystemImage: "arrow.uturn.backward"
                )
            case .filter:
                undoable(
                    title: .app("View.DiagramEmptyScopeOverlay.NothingMatchesThisFilter"),
                    detail: .app("View.DiagramEmptyScopeOverlay.FilterHidEverything"),
                    systemImage: "line.3.horizontal.decrease.circle",
                    undoTitle: .app("View.DiagramEmptyScopeOverlay.ClearFilter"),
                    undoSystemImage: "line.3.horizontal.decrease.circle.fill"
                )
            case .scopeAndFilter:
                undoable(
                    title: .app("View.DiagramEmptyScopeOverlay.NothingMatchesThisScopeAndFilter"),
                    detail: .app("View.DiagramEmptyScopeOverlay.ScopeAndFilterHidEverything"),
                    systemImage: "scope",
                    undoTitle: .app("View.DiagramEmptyScopeOverlay.ResetScopeAndFilter"),
                    undoSystemImage: "arrow.uturn.backward"
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("diagram.emptyScope.\(reason.rawValue)")
    }

    private func undoable(
        title: LocalizedStringResource,
        detail: LocalizedStringResource,
        systemImage: String,
        undoTitle: LocalizedStringResource,
        undoSystemImage: String
    ) -> some View {
        ContentUnavailableView {
            Label {
                Text(localized: title)
            } icon: {
                Image(systemName: systemImage)
            }
        } description: {
            Text(localized: detail)
        } actions: {
            Button(action: onUndo) {
                Label(undoTitle, systemImage: undoSystemImage)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("diagram.emptyScope.actionButton")
        }
    }
}
