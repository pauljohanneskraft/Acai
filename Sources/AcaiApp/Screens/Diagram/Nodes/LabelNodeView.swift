import SwiftUI
import AcaiRender

struct LabelNodeView: View {
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

    private var decorations: FreeformDecorationColors { palette.freeformDecorations }

    private var fill: Color { role == .actor ? decorations.actorFill : decorations.databaseFill }
    private var border: Color { role == .actor ? decorations.actorBorder : decorations.databaseBorder }
    private var icon: Color { role == .actor ? decorations.actorIcon : decorations.databaseIcon }

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: role.systemImageName)
                .font(.system(size: 28))
                .foregroundColor(icon)
            Text(verbatim: name)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(palette.canvasInk.primaryInk)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .background(fill)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor : border, lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }
}
