import SwiftUI

/// A call-graph method node: a rounded monospaced box labelled `Type.method` (or a bare
/// function name). Used both by the freeform editor's `.method` nodes and as the visual match
/// for a call graph saved as freeform.
struct MethodNodeView: View {
    let name: String
    let isSelected: Bool

    var body: some View {
        Text(name)
            .font(.system(.caption, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.89, green: 0.95, blue: 0.99)))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color(white: 0.6),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
    }
}
