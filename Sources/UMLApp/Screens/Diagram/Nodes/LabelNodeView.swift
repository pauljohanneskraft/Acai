import SwiftUI
import UMLRender

struct LabelNodeView: View {
    /// Which labelled role this node represents; drives the icon and the palette colours.
    enum Role {
        case actor, database

        var systemImageName: String {
            switch self {
            case .actor:
                "person"
            case .database:
                "cylinder"
            }
        }
    }

    static func actor(name: String, isSelected: Bool) -> LabelNodeView {
        .init(name: name, role: .actor, isSelected: isSelected)
    }

    static func database(name: String, isSelected: Bool) -> LabelNodeView {
        .init(name: name, role: .database, isSelected: isSelected)
    }

    let name: String
    let role: Role
    let isSelected: Bool

    @Environment(\.diagramPalette) private var palette

    private var fill: Color { role == .actor ? palette.actorFill : palette.databaseFill }
    private var border: Color { role == .actor ? palette.actorBorder : palette.databaseBorder }
    private var icon: Color { role == .actor ? palette.actorIcon : palette.databaseIcon }

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: role.systemImageName)
                .font(.system(size: 28))
                .foregroundColor(icon)
            Text(name)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(palette.primaryInk)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(fill)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor : border, lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }
}
