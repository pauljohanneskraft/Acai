import SwiftUI
import UMLRender

struct StereotypedBoxNodeView: View {
    let name: String
    let stereotype: String?
    let systemImage: String
    let isSelected: Bool

    @Environment(\.diagramPalette) private var palette

    var body: some View {
        VStack(spacing: 4) {
            if let stereotype {
                Text("<<\(stereotype)>>")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(palette.artifactBorder)
            }
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 14))
                    .foregroundColor(palette.artifactIcon)
                Text(name)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(palette.primaryInk)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(palette.artifactFill)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? Color.accentColor : palette.artifactBorder, lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }
}
