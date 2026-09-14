import SwiftUI
import AcaiDiff

/// Non-color complement to a delta tint (`deltaHex`/border/fill colour): a small glyph badge so a
/// changed element's status is never colour-alone. Shared by every node view that supports
/// comparison (`TypeNodeView`, call-graph/package/sequence/state nodes).
public struct DeltaBadgeView: View {
    let status: DeltaStatus

    public init(status: DeltaStatus) {
        self.status = status
    }

    public var body: some View {
        Text(status.badgeGlyph ?? "")
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(.white)
            .frame(width: 15, height: 15)
            .background(Circle().fill(fill))
            .overlay(Circle().stroke(Color.white, lineWidth: 1))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(status.badgeAccessibilityLabel ?? "")
    }

    private var fill: Color {
        status.deltaHex.map { Color(hex: $0) } ?? Color.secondary
    }
}

extension View {
    /// Overlays `DeltaBadgeView` in the top-trailing corner when `status` carries a glyph, so a
    /// changed diagram element (a node, a participant, a state, …) is never colour-alone. `nil`
    /// leaves the view untouched — no badge, matching an unchanged element or a non-delta diagram.
    @ViewBuilder
    public func deltaBadge(_ status: DeltaStatus?) -> some View {
        if let status, status.badgeGlyph != nil {
            overlay(alignment: .topTrailing) {
                DeltaBadgeView(status: status).offset(x: 7, y: -7)
            }
        } else {
            self
        }
    }
}
