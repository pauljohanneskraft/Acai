import SwiftUI
import AcaiDiagram

/// A single state-machine node, styled per its UML kind: filled circle (initial),
/// bullseye (final), diamond (choice), bar (fork/join), rounded rectangle with the
/// title and optional `entry/exit/do` rows (normal/composite — composites render
/// flat, without nested substates, in this version).
///
/// Shared by the generated state-diagram canvas, the static snapshot, and the
/// freeform-diagram editor so all three look identical. Fixed light fills with
/// explicit ink text, matching `TypeNodeView`'s visual language.
public struct StateNodeView: View {
    let name: String
    let kind: StateDiagram.State.Kind
    let entryAction: String?
    let exitAction: String?
    let doActivity: String?
    let isSelected: Bool

    public init(
        name: String,
        kind: StateDiagram.State.Kind,
        entryAction: String? = nil,
        exitAction: String? = nil,
        doActivity: String? = nil,
        isSelected: Bool = false
    ) {
        self.name = name
        self.kind = kind
        self.entryAction = entryAction
        self.exitAction = exitAction
        self.doActivity = doActivity
        self.isSelected = isSelected
    }

    public init(state: StateDiagram.State, isSelected: Bool = false) {
        self.init(
            name: state.name,
            kind: state.kind,
            entryAction: state.entryAction,
            exitAction: state.exitAction,
            doActivity: state.doActivity,
            isSelected: isSelected
        )
    }

    @Environment(\.diagramPalette) private var palette

    private var ink: Color { palette.primaryInk }
    private var borderColor: Color { isSelected ? .accentColor : palette.neutralBorder }
    private var borderWidth: CGFloat { isSelected ? 2 : 1 }

    public var body: some View {
        switch kind {
        case .initial:
            Circle()
                .fill(palette.stateSolidFill)
                .overlay(Circle().stroke(borderColor, lineWidth: isSelected ? 2 : 0))
        case .final:
            ZStack {
                Circle().stroke(borderColor, lineWidth: borderWidth)
                Circle().inset(by: 5).fill(palette.stateSolidFill)
            }
        case .choice:
            DiamondShape()
                .fill(palette.choiceBackground)
                .overlay(DiamondShape().stroke(borderColor, lineWidth: borderWidth))
                .overlay(
                    Text(name)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(ink)
                        .lineLimit(1)
                )
        case .fork, .join:
            RoundedRectangle(cornerRadius: 2)
                .fill(palette.stateSolidFill)
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(borderColor, lineWidth: isSelected ? 2 : 0))
        case .normal, .composite:
            stateBox
        }
    }

    private var stateBox: some View {
        VStack(spacing: 2) {
            Text(name)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(ink)
                .lineLimit(1)
            ForEach(actionRows, id: \.self) { row in
                Text(row)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(palette.mutedInk)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
        .background(palette.stateBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(borderColor, lineWidth: borderWidth)
        )
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }

    private var actionRows: [String] {
        var rows: [String] = []
        if let entryAction { rows.append("entry / \(entryAction)") }
        if let exitAction { rows.append("exit / \(exitAction)") }
        if let doActivity { rows.append("do / \(doActivity)") }
        return rows
    }
}

/// A diamond (rotated square) inscribed in the view's bounds.
public struct DiamondShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Ensemble (transition edges)

/// The transition arrows of a state diagram, drawn from a pre-computed
/// `StateLayoutModel`. Callers (snapshot, generated canvas) draw their own
/// node views on top so selection/drag behaviour stays caller-specific.
public struct StateEnsembleView: View {
    let layout: StateLayoutModel
    /// Optional per-transition delta tint, keyed on the edge. `nil` leaves the theme colour, so the
    /// app canvas / freeform editor are unaffected.
    let edgeColor: (@Sendable (StateLayoutModel.EdgeLayout) -> Color?)?

    public init(
        layout: StateLayoutModel,
        edgeColor: (@Sendable (StateLayoutModel.EdgeLayout) -> Color?)? = nil
    ) {
        self.layout = layout
        self.edgeColor = edgeColor
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.edges) { edge in
                if let sourceRect = layout.frame(for: edge.from),
                   let targetRect = layout.frame(for: edge.to) {
                    RelationshipEdgeView(
                        kind: .association,
                        sourceRect: sourceRect,
                        targetRect: targetRect,
                        label: edge.label,
                        strokeColor: edgeColor?(edge)
                    )
                }
            }
        }
    }
}

// MARK: - Snapshot

/// A static rendering of a `StateDiagram` from a pre-computed `StateLayoutModel`:
/// transition arrows plus state nodes. Shared by the CLI image export and "save
/// as image" — mirroring `SequenceDiagramSnapshotView`.
public struct StateDiagramSnapshotView: View {
    let layout: StateLayoutModel
    let padding: CGFloat
    let selectedStateID: String?
    let palette: DiagramPalette
    let edgeColor: (@Sendable (StateLayoutModel.EdgeLayout) -> Color?)?

    public init(
        layout: StateLayoutModel,
        padding: CGFloat = 40,
        selectedStateID: String? = nil,
        palette: DiagramPalette = .light,
        edgeColor: (@Sendable (StateLayoutModel.EdgeLayout) -> Color?)? = nil
    ) {
        self.layout = layout
        self.padding = padding
        self.selectedStateID = selectedStateID
        self.palette = palette
        self.edgeColor = edgeColor
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            StateEnsembleView(layout: layout, edgeColor: edgeColor)

            ForEach(layout.nodes) { node in
                StateNodeView(state: node.state, isSelected: node.id == selectedStateID)
                    .frame(width: node.rect.width, height: node.rect.height)
                    .position(x: node.rect.midX, y: node.rect.midY)
            }
        }
        .frame(width: layout.contentSize.width, height: layout.contentSize.height, alignment: .topLeading)
        .padding(padding)
        .background(palette.canvasBackground)
        .environment(\.diagramPalette, palette)
    }
}
