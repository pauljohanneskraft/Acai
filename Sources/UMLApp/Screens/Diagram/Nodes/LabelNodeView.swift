import SwiftUI

struct LabelNodeView: View {
    private static let actorBackgroundColor = Color(red: 0.95, green: 0.99, blue: 0.99)
    private static let actorBorderColor = Color(red: 0.45, green: 0.72, blue: 0.72)
    private static let actorIconColor = Color(red: 0.30, green: 0.60, blue: 0.60)

    static func actor(
        name: String,
        isSelected: Bool
    ) -> LabelNodeView {
        .init(
            name: name,
            systemImageName: "person",
            isSelected: isSelected,
            backgroundColor: actorBackgroundColor,
            iconColor: actorIconColor,
            borderColor: actorBorderColor
        )
    }

    private static let databaseBackgroundColor = Color(red: 1.0, green: 0.96, blue: 0.97)
    private static let databaseBorderColor = Color(red: 0.82, green: 0.52, blue: 0.58)
    private static let databaseIconColor = Color(red: 0.72, green: 0.40, blue: 0.48)

    static func database(
        name: String,
        isSelected: Bool
    ) -> LabelNodeView {
        .init(
            name: name,
            systemImageName: "cylinder",
            isSelected: isSelected,
            backgroundColor: databaseBackgroundColor,
            iconColor: databaseIconColor,
            borderColor: databaseBorderColor
        )
    }

    let name: String
    let systemImageName: String
    let isSelected: Bool
    let backgroundColor: Color
    let iconColor: Color
    let borderColor: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemImageName)
                .font(.system(size: 28))
                .foregroundColor(iconColor)
            Text(name)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(Color(white: 0.1))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor : borderColor, lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }
}
