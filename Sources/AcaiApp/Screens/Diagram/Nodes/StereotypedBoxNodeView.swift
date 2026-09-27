import SwiftUI
import AcaiRender

struct StereotypedBoxNodeView: View {
    let name: String
    let stereotype: String?
    let systemImage: String
    let isSelected: Bool

    @Environment(\.diagramPalette) private var palette

    var body: some View {
        VStack(spacing: .spacingXS) {
            if let stereotype {
                Text(verbatim: "<<\(stereotype)>>")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(palette.freeformDecorations.artifactBorder)
            }
            HStack(spacing: .spacingXS) {
                Image(systemName: systemImage)
                    .font(.system(size: 14))
                    .foregroundColor(palette.freeformDecorations.artifactIcon)
                Text(verbatim: name)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(palette.canvasInk.primaryInk)
            }
        }
        .padding(.horizontal, .spacingM)
        .padding(.vertical, .spacingS)
        .background(palette.freeformDecorations.artifactFill)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(
                    isSelected ? Color.accentColor : palette.freeformDecorations.artifactBorder,
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }
}
