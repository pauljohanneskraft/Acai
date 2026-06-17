import SwiftUI
import UMLRender

struct NoteNodeView: View {
    let name: String
    let text: String
    let isSelected: Bool

    @Environment(\.diagramPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !name.isEmpty {
                Text(name)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(palette.primaryInk)
            }
            Text(text.isEmpty ? "(empty note)" : text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(text.isEmpty ? palette.mutedInk : palette.secondaryInk)
                .lineLimit(8)
        }
        .padding(10)
        .frame(minWidth: 100, alignment: .leading)
        .background(palette.noteFill)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(isSelected ? Color.accentColor : palette.noteBorder, lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }
}
