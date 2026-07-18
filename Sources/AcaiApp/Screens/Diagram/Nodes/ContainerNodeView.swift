import SwiftUI
import AcaiRender

struct ContainerNodeView: View {
    let name: String
    let stereotype: String
    let style: Style
    let isSelected: Bool
    let size: CGSize?
    /// Overrides the style's body fill (e.g. the package diagram's zone-of-pain tint).
    /// `nil` keeps the style's default fill, so freeform `.package` nodes look unchanged.
    var fillColor: Color?

    init(
        name: String,
        stereotype: String,
        style: Style,
        isSelected: Bool,
        size: CGSize?,
        fillColor: Color? = nil
    ) {
        self.name = name
        self.stereotype = stereotype
        self.style = style
        self.isSelected = isSelected
        self.size = size
        self.fillColor = fillColor
    }

    enum Style {
        case package, boundary, subsystem

        /// The palette colour family backing this style.
        var tint: ContainerTint {
            switch self {
            case .package:
                .package
            case .boundary:
                .boundary
            case .subsystem:
                .subsystem
            }
        }

        var isDashed: Bool {
            self == .boundary
        }
    }

    @Environment(\.diagramPalette) private var palette

    var body: some View {
        let width = size?.width ?? 200
        let height = size?.height ?? 150
        let styleBorder = palette.containerBorder(style.tint)
        let border = isSelected ? Color.accentColor : styleBorder
        let lineWidth: CGFloat = isSelected ? 2 : 1

        VStack(alignment: .leading, spacing: 0) {
            // Header with stereotype + name
            VStack(spacing: 1) {
                Text("<<\(stereotype)>>")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(styleBorder)
                Text(name)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(palette.primaryInk)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(palette.containerHeader(style.tint))

            // Divider
            Rectangle()
                .fill(border)
                .frame(height: lineWidth)

            // Open body area
            Spacer()
        }
        .frame(width: width, height: height)
        .background(fillColor ?? palette.containerFill(style.tint))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(border, style: style.isDashed
                    ? StrokeStyle(lineWidth: lineWidth, dash: [6, 4])
                    : StrokeStyle(lineWidth: lineWidth))
        )
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }
}
