import SwiftUI
import AcaiRender

struct UseCaseNodeView: View {
    let name: String
    let isSelected: Bool

    @Environment(\.diagramPalette) private var palette

    var body: some View {
        Text(verbatim: name)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundColor(palette.canvasInk.primaryInk)
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.m)
            .background(palette.freeformDecorations.useCaseFill)
            .clipShape(Ellipse())
            .overlay(
                Ellipse()
                    .stroke(
                        isSelected ? Color.accentColor : palette.freeformDecorations.useCaseBorder,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }
}
