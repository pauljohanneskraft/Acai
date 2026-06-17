import SwiftUI
import UMLRender

/// A call-graph method node: a rounded monospaced box labelled `Type.method` (or a bare
/// function name). Used both by the freeform editor's `.method` nodes and as the visual match
/// for a call graph saved as freeform.
struct MethodNodeView: View {
    let name: String
    let isSelected: Bool

    @Environment(\.diagramPalette) private var palette

    var body: some View {
        Text(name)
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(palette.primaryInk)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 8).fill(palette.methodFill))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isSelected ? Color.accentColor : palette.methodBorder,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
    }
}
