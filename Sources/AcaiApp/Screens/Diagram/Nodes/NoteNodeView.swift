import SwiftUI
import AcaiRender

struct NoteNodeView: View {
    let name: String
    let text: String
    let isSelected: Bool

    @Environment(\.diagramPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if !name.isEmpty {
                Text(verbatim: name)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(palette.canvasInk.primaryInk)
            }
            (text.isEmpty ? Text(.app("View.NoteNodeView.EmptyNote")) : Text(verbatim: text))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(text.isEmpty ? palette.canvasInk.mutedInk : palette.canvasInk.secondaryInk)
                .lineLimit(8)
        }
        .padding(Spacing.s)
        .frame(minWidth: 100, alignment: .leading)
        .background(palette.freeformDecorations.noteFill)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(
                    isSelected ? Color.accentColor : palette.freeformDecorations.noteBorder,
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }
}
