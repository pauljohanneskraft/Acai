import SwiftUI
import AcaiCore

/// Renders one property/method line of a UML type box: the shared row used by both the canvas
/// (`TypeNodeView`, `compact: true`) and the inspector's member lists (`compact: false`).
///
/// `compact` rows render byte-identically to the pre-existing canvas text (no weight change, no
/// icon): `DiagramLayoutModel.estimateSize`'s char-count width heuristic drives the headless CLI
/// renderer, where no live SwiftUI measurement ever runs, and the committed `Examples/` class PNGs
/// (regenerated only when their content is meant to change) proved a `.semibold` public/open row
/// already shifts glyph widths enough to fail the pixel-diff regression. Non-compact rows have no
/// such constraint, so they carry the full access-level affordance: weight and a leading glyph.
public struct MemberRowView: View {
    let item: MemberDisplayItem
    let compact: Bool

    @Environment(\.diagramPalette) private var palette

    public init(item: MemberDisplayItem, compact: Bool) {
        self.item = item
        self.compact = compact
    }

    public var body: some View {
        if compact {
            Text(item.text)
                .font(.system(size: 11, design: .monospaced))
                .if(item.isStatic) { $0.underline() }
                .if(item.isAbstract) { $0.italic() }
                .foregroundColor(palette.secondaryInk)
                .lineLimit(1)
        } else {
            HStack(spacing: 4) {
                Image(systemName: item.accessLevel.rowSymbolName)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .frame(width: 12)
                Text(item.text)
                    .font(.system(size: 12, design: .monospaced))
                    .fontWeight(item.accessLevel.isEmphasized ? .semibold : .regular)
                    .if(item.isStatic) { $0.underline() }
                    .if(item.isAbstract) { $0.italic() }
                    .lineLimit(1)
            }
            .foregroundColor(.primary)
        }
    }
}

extension AccessLevel {
    fileprivate var isEmphasized: Bool {
        self == .public || self == .open
    }

    /// A leading SF Symbol grouped the same way `umlSymbol` already groups access levels for UML
    /// notation, so the icon and the glyph it stands in for never disagree.
    fileprivate var rowSymbolName: String {
        switch self {
        case .public, .open:
            "globe"
        case .internal, .packagePrivate:
            "shippingbox"
        case .protected:
            "person.2"
        case .private, .filePrivate:
            "lock"
        }
    }
}
