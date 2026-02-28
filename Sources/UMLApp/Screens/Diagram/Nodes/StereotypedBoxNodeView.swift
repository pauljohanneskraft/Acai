import SwiftUI

struct StereotypedBoxNodeView: View {
    let name: String
    let stereotype: String?
    let systemImage: String
    let isSelected: Bool

    private let backgroundColor = Color(red: 0.95, green: 0.98, blue: 0.99)
    private let borderColor = Color(red: 0.40, green: 0.65, blue: 0.75)
    private let iconColor = Color(red: 0.30, green: 0.55, blue: 0.65)

    var body: some View {
        VStack(spacing: 4) {
            if let stereotype {
                Text("<<\(stereotype)>>")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(borderColor)
            }
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 14))
                    .foregroundColor(iconColor)
                Text(name)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(white: 0.1))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? Color.accentColor : borderColor, lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }
}
