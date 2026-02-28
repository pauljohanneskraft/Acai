import SwiftUI

struct NoteNodeView: View {
    let name: String
    let text: String
    let isSelected: Bool

    private let backgroundColor = Color(red: 1.0, green: 0.99, blue: 0.94)
    private let borderColor = Color(red: 0.82, green: 0.75, blue: 0.42)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !name.isEmpty {
                Text(name)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(white: 0.1))
            }
            Text(text.isEmpty ? "(empty note)" : text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(text.isEmpty ? Color(white: 0.5) : Color(white: 0.15))
                .lineLimit(8)
        }
        .padding(10)
        .frame(minWidth: 100, alignment: .leading)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(isSelected ? Color.accentColor : borderColor, lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }
}
