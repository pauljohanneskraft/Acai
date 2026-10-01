import SwiftUI

/// Why a diagram canvas has no nodes to lay out. A pannable, silent canvas reads the same whether
/// the codebase has none of this kind or the viewer's own narrowing hid all of it, which is the
/// distinction this drives: only `scope` and `filter` have something to undo.
enum DiagramEmptyReason: String, Equatable, Sendable {
    case codebase
    case scope
    case filter
}

/// Shown over a generated diagram's canvas whenever its laid-out node set is empty, so the canvas
/// never reads as "still rendering". Shared by all five generated diagram types; each supplies only
/// the sentence for `.codebase`, since "no state machines" and "no modules" differ while "nothing
/// matches this filter" does not.
struct DiagramEmptyScopeOverlay: View {
    let reason: DiagramEmptyReason
    let nothingOfThisKind: LocalizedStringResource
    let onUndo: () -> Void

    var body: some View {
        VStack(spacing: .spacingL) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(localized: title)
                .font(.title3)
                .multilineTextAlignment(.center)
            Text(localized: detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let undoTitle {
                Button(undoTitle, action: onUndo)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("diagram.emptyScope.undoButton")
            }
        }
        .padding(.spacingXL)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(localized: title))
        .accessibilityIdentifier("diagram.emptyScope.\(reason.rawValue)")
    }

    private var icon: String {
        switch reason {
        case .codebase: "square.dashed"
        case .scope: "scope"
        case .filter: "line.3.horizontal.decrease.circle"
        }
    }

    private var title: LocalizedStringResource {
        switch reason {
        case .codebase: nothingOfThisKind
        case .scope: .app("View.DiagramEmptyScopeOverlay.NothingMatchesThisScope")
        case .filter: .app("View.DiagramEmptyScopeOverlay.NothingMatchesThisFilter")
        }
    }

    private var detail: LocalizedStringResource {
        switch reason {
        case .codebase: .app("View.DiagramEmptyScopeOverlay.NothingToUndo")
        case .scope: .app("View.DiagramEmptyScopeOverlay.ScopeHidEverything")
        case .filter: .app("View.DiagramEmptyScopeOverlay.FilterHidEverything")
        }
    }

    private var undoTitle: LocalizedStringResource? {
        switch reason {
        case .codebase: nil
        case .scope: .app("View.DiagramEmptyScopeOverlay.ResetScope")
        case .filter: .app("View.DiagramEmptyScopeOverlay.ClearFilter")
        }
    }
}
