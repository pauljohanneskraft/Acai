import SwiftUI

/// `scope` and `filter` are narrowings the viewer applied and can undo in one tap; `codebase` is the
/// codebase itself having none of this kind, with no undo to offer.
enum DiagramEmptyReason: String, Equatable, Sendable {
    case codebase
    case scope
    case filter
}

struct DiagramEmptyAction {
    let title: LocalizedStringResource
    let systemImage: String
    let perform: () -> Void
}

struct DiagramEmptyDescription {
    let systemImage: String
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    var action: DiagramEmptyAction?
}

/// Shown over an empty canvas, which would otherwise read as one that has not rendered yet.
struct DiagramEmptyScopeOverlay: View {
    let reason: DiagramEmptyReason
    let nothingOfThisKind: DiagramEmptyDescription
    let onUndo: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(localized: title)
            } icon: {
                Image(systemName: systemImage)
            }
        } description: {
            Text(localized: detail)
        } actions: {
            if let action {
                Button(action: action.perform) {
                    Label(action.title, systemImage: action.systemImage)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("diagram.emptyScope.actionButton")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("diagram.emptyScope.\(reason.rawValue)")
    }

    private var systemImage: String {
        switch reason {
        case .codebase:
            nothingOfThisKind.systemImage
        case .scope:
            "scope"
        case .filter:
            "line.3.horizontal.decrease.circle"
        }
    }

    private var title: LocalizedStringResource {
        switch reason {
        case .codebase:
            nothingOfThisKind.title
        case .scope:
            .app("View.DiagramEmptyScopeOverlay.NothingMatchesThisScope")
        case .filter:
            .app("View.DiagramEmptyScopeOverlay.NothingMatchesThisFilter")
        }
    }

    private var detail: LocalizedStringResource {
        switch reason {
        case .codebase:
            nothingOfThisKind.detail
        case .scope:
            .app("View.DiagramEmptyScopeOverlay.ScopeHidEverything")
        case .filter:
            .app("View.DiagramEmptyScopeOverlay.FilterHidEverything")
        }
    }

    private var action: DiagramEmptyAction? {
        switch reason {
        case .codebase:
            nothingOfThisKind.action
        case .scope:
            DiagramEmptyAction(
                title: .app("View.DiagramEmptyScopeOverlay.ResetScope"),
                systemImage: "arrow.uturn.backward",
                perform: onUndo
            )
        case .filter:
            DiagramEmptyAction(
                title: .app("View.DiagramEmptyScopeOverlay.ClearFilter"),
                systemImage: "line.3.horizontal.decrease.circle.fill",
                perform: onUndo
            )
        }
    }
}
