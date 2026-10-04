import SwiftUI

/// Why a generated diagram's canvas has no nodes to lay out. `scope` and `filter` are narrowings the
/// viewer applied and can undo in one tap; `codebase` is the codebase itself having none of this kind.
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

/// A diagram type's own account of the codebase having none of its kind — "no state machines" and
/// "no modules" read differently, and so does what to do about them.
struct DiagramEmptyDescription {
    let systemImage: String
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    var action: DiagramEmptyAction?
}

/// Shown over a generated diagram's canvas whenever its laid-out node set is empty, so a pannable,
/// silent canvas never reads as one that has not rendered yet.
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
