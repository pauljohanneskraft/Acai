import SwiftUI

struct UseCaseNodeView: View {
    let name: String
    let isSelected: Bool

    private let backgroundColor = Color(red: 0.96, green: 0.95, blue: 1.0)
    private let borderColor = Color(red: 0.58, green: 0.52, blue: 0.82)

    var body: some View {
        Text(name)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundColor(Color(white: 0.1))
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(backgroundColor)
            .clipShape(Ellipse())
            .overlay(
                Ellipse()
                    .stroke(isSelected ? Color.accentColor : borderColor, lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }
}
