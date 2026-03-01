import SwiftUI

struct ContainerNodeView: View {
    let name: String
    let stereotype: String
    let style: Style
    let isSelected: Bool
    let size: CGSize?

    enum Style {
        case package, boundary, subsystem

        var fillColor: Color {
            switch self {
            case .package:
                Color(red: 0.96, green: 0.93, blue: 0.88)
            case .boundary:
                Color(red: 1.0, green: 0.97, blue: 0.90)
            case .subsystem:
                Color(red: 0.90, green: 0.96, blue: 0.98)
            }
        }

        var headerColor: Color {
            switch self {
            case .package:
                Color(red: 0.91, green: 0.86, blue: 0.78)
            case .boundary:
                Color(red: 0.96, green: 0.92, blue: 0.82)
            case .subsystem:
                Color(red: 0.82, green: 0.92, blue: 0.96)
            }
        }

        var borderColor: Color {
            switch self {
            case .package:
                Color(red: 0.68, green: 0.58, blue: 0.42)
            case .boundary:
                Color(red: 0.78, green: 0.65, blue: 0.35)
            case .subsystem:
                Color(red: 0.40, green: 0.65, blue: 0.75)
            }
        }

        var isDashed: Bool {
            self == .boundary
        }
    }

    var body: some View {
        let width = size?.width ?? 200
        let height = size?.height ?? 150
        let border = isSelected ? Color.accentColor : style.borderColor
        let lineWidth: CGFloat = isSelected ? 2 : 1

        VStack(alignment: .leading, spacing: 0) {
            // Header with stereotype + name
            VStack(spacing: 1) {
                Text("<<\(stereotype)>>")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(style.borderColor)
                Text(name)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(white: 0.1))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(style.headerColor)

            // Divider
            Rectangle()
                .fill(border)
                .frame(height: lineWidth)

            // Open body area
            Spacer()
        }
        .frame(width: width, height: height)
        .background(style.fillColor)
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
