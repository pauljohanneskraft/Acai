import SwiftUI
import AcaiDiagram

/// A static rendering of a `SequenceDiagram` from a pre-computed `SequenceLayoutModel`:
/// participant headers, dashed lifelines and time-ordered message arrows. Shared by the live
/// app canvas (which overlays gestures on top) and the CLI image export — mirroring how
/// `DiagramSnapshotView` backs the class diagram.
///
/// Coordinates come straight from the layout model (top-left at the origin); the view sizes
/// itself to `layout.contentSize` plus a uniform `padding`.
public struct SequenceDiagramSnapshotView: View {
    let layout: SequenceLayoutModel
    let padding: CGFloat
    let selectedParticipantID: String?
    let palette: DiagramPalette
    let messageColor: (@Sendable (SequenceLayoutModel.MessageLayout) -> Color?)?

    public init(
        layout: SequenceLayoutModel,
        padding: CGFloat = 40,
        selectedParticipantID: String? = nil,
        palette: DiagramPalette = .light,
        messageColor: (@Sendable (SequenceLayoutModel.MessageLayout) -> Color?)? = nil
    ) {
        self.layout = layout
        self.padding = padding
        self.selectedParticipantID = selectedParticipantID
        self.palette = palette
        self.messageColor = messageColor
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            SequenceEnsembleView(layout: layout, messageColor: messageColor)

            // Participant headers on top.
            ForEach(layout.participants) { participant in
                SequenceParticipantHeader(
                    participant: participant,
                    isSelected: participant.id == selectedParticipantID
                )
                .frame(width: participant.headerRect.width, height: participant.headerRect.height)
                .position(x: participant.headerRect.midX, y: participant.headerRect.midY)
            }
        }
        .frame(width: layout.contentSize.width, height: layout.contentSize.height, alignment: .topLeading)
        .padding(padding)
        .background(palette.canvasBackground)
        .environment(\.diagramPalette, palette)
    }
}

// MARK: - Ensemble (lifelines + activations + messages)

/// The non-interactive body of a sequence diagram — dashed lifelines, execution-occurrence bars
/// and message arrows — without the participant headers. Shared by the static snapshot, the
/// generated-diagram canvas and the freeform-diagram editor so all three look identical; callers
/// draw their own (interactive or plain) headers on top.
public struct SequenceEnsembleView: View {
    let layout: SequenceLayoutModel
    /// Optional per-message delta tint, keyed on the message's layout id. `nil` leaves all
    /// messages the theme colour (so the app canvas / freeform editor are unaffected).
    let messageColor: (@Sendable (SequenceLayoutModel.MessageLayout) -> Color?)?

    public init(
        layout: SequenceLayoutModel,
        messageColor: (@Sendable (SequenceLayoutModel.MessageLayout) -> Color?)? = nil
    ) {
        self.layout = layout
        self.messageColor = messageColor
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.participants) { participant in
                SequenceLifelineView(participant: participant)
            }
            ForEach(layout.activations) { bar in
                SequenceActivationBarView(bar: bar)
            }
            ForEach(layout.messages) { message in
                SequenceMessageView(message: message, deltaColor: messageColor?(message))
            }
            // Fragment frames on top: their borders and labels must stay visible over arrows.
            ForEach(layout.fragments) { fragment in
                SequenceFragmentView(fragment: fragment)
            }
        }
    }
}

// MARK: - Combined Fragment

/// A UML 2 combined-fragment frame: a rectangle around the covered message rows with the
/// operator name in a pentagon tab at the top-left, guard conditions in brackets, and dashed
/// separators between operands (for `alt` / `par`).
public struct SequenceFragmentView: View {
    let fragment: SequenceLayoutModel.FragmentFrame
    let isSelected: Bool

    public init(fragment: SequenceLayoutModel.FragmentFrame, isSelected: Bool = false) {
        self.fragment = fragment
        self.isSelected = isSelected
    }

    @Environment(\.diagramPalette) private var palette

    private var ink: Color { palette.secondaryInk }
    private var borderColor: Color { isSelected ? .accentColor : palette.neutralBorder }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            // Frame.
            Rectangle()
                .strokeBorder(borderColor, lineWidth: isSelected ? 2 : 1)
                .frame(width: fragment.rect.width, height: fragment.rect.height)
                .position(x: fragment.rect.midX, y: fragment.rect.midY)

            // Operand separators.
            ForEach(Array(fragment.separatorYs.enumerated()), id: \.offset) { _, y in
                Path { path in
                    path.move(to: CGPoint(x: fragment.rect.minX, y: y))
                    path.addLine(to: CGPoint(x: fragment.rect.maxX, y: y))
                }
                .stroke(borderColor, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            }

            // Operator tab (pentagon).
            tab

            // Guards.
            ForEach(Array(fragment.guards.enumerated()), id: \.offset) { _, guardInfo in
                Text(guardInfo.label)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(ink)
                    .position(x: fragment.rect.midX, y: guardInfo.y)
            }
        }
    }

    private var tab: some View {
        let label = fragment.kind.rawValue
        let width = fragment.tabRect.width
        let height = fragment.tabRect.height
        let origin = fragment.tabRect.origin
        return ZStack {
            Path { path in
                // Pentagon: rectangle with a clipped bottom-right corner.
                path.move(to: origin)
                path.addLine(to: CGPoint(x: origin.x + width, y: origin.y))
                path.addLine(to: CGPoint(x: origin.x + width, y: origin.y + height * 0.55))
                path.addLine(to: CGPoint(x: origin.x + width - 8, y: origin.y + height))
                path.addLine(to: CGPoint(x: origin.x, y: origin.y + height))
                path.closeSubpath()
            }
            .fill(palette.subtleSurface)
            Path { path in
                path.move(to: origin)
                path.addLine(to: CGPoint(x: origin.x + width, y: origin.y))
                path.addLine(to: CGPoint(x: origin.x + width, y: origin.y + height * 0.55))
                path.addLine(to: CGPoint(x: origin.x + width - 8, y: origin.y + height))
                path.addLine(to: CGPoint(x: origin.x, y: origin.y + height))
                path.closeSubpath()
            }
            .stroke(borderColor, lineWidth: 1)
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(palette.primaryInk)
                .position(x: origin.x + width / 2 - 3, y: origin.y + height / 2)
        }
    }
}

// MARK: - Activation Bar

/// An execution occurrence ("focus of control"): the thin rectangle on a lifeline marking the
/// span during which the participant is processing a message.
public struct SequenceActivationBarView: View {
    let bar: SequenceLayoutModel.ActivationBar

    public init(bar: SequenceLayoutModel.ActivationBar) {
        self.bar = bar
    }

    @Environment(\.diagramPalette) private var palette

    public var body: some View {
        Rectangle()
            .fill(palette.subtleSurface)
            .overlay(Rectangle().strokeBorder(palette.neutralBorder, lineWidth: 1))
            .frame(width: bar.rect.width, height: bar.rect.height)
            .position(x: bar.rect.midX, y: bar.rect.midY)
    }
}

// MARK: - Lifeline

/// The dashed vertical lifeline dropping from a participant header.
public struct SequenceLifelineView: View {
    let participant: SequenceLayoutModel.ParticipantFrame

    public init(participant: SequenceLayoutModel.ParticipantFrame) {
        self.participant = participant
    }

    @Environment(\.diagramPalette) private var palette

    public var body: some View {
        Path { path in
            path.move(to: CGPoint(x: participant.lifelineX, y: participant.lifelineTop))
            path.addLine(to: CGPoint(x: participant.lifelineX, y: participant.lifelineBottom))
        }
        .stroke(palette.edgeLine, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
    }
}

// MARK: - Participant Header

/// A lifeline header box, styled by the participant's role.
public struct SequenceParticipantHeader: View {
    let participant: SequenceLayoutModel.ParticipantFrame
    let isSelected: Bool

    public init(participant: SequenceLayoutModel.ParticipantFrame, isSelected: Bool = false) {
        self.participant = participant
        self.isSelected = isSelected
    }

    public var body: some View {
        ParticipantHeaderView(name: participant.name, kind: participant.kind, isSelected: isSelected)
    }
}

/// A standalone participant header (name + role stereotype), reused by the sequence snapshot and
/// the freeform-diagram lifeline node so both look identical.
///
/// Styled in the same visual language as `TypeNodeView` (fixed light fills with explicit ink
/// text, monospaced fonts, kind-tinted border) so sequence diagrams match the rest of the app —
/// and stay readable in dark mode, where dynamic colors would invert against the light canvas.
public struct ParticipantHeaderView: View {
    let name: String
    let kind: SequenceDiagram.Participant.Kind
    let isSelected: Bool

    public init(name: String, kind: SequenceDiagram.Participant.Kind, isSelected: Bool = false) {
        self.name = name
        self.kind = kind
        self.isSelected = isSelected
    }

    @Environment(\.diagramPalette) private var palette

    public var body: some View {
        VStack(spacing: 2) {
            if let stereotype = kind.stereotype {
                Text("<<\(stereotype)>>")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(palette.participantAccent(for: kind))
            }
            Text(name)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(palette.primaryInk)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 10)
        .background(palette.participantFill(for: kind))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(
                    isSelected ? Color.accentColor : palette.participantBorder(for: kind),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }
}

// MARK: - Message

/// A single message arrow (or self-loop) at its laid-out vertical position.
public struct SequenceMessageView: View {
    let message: SequenceLayoutModel.MessageLayout
    /// Per-message delta tint (added/removed). `nil` uses the theme's edge colour.
    let deltaColor: Color?

    public init(message: SequenceLayoutModel.MessageLayout, deltaColor: Color? = nil) {
        self.message = message
        self.deltaColor = deltaColor
    }

    @Environment(\.diagramPalette) private var palette

    private var color: Color { deltaColor ?? palette.edgeLine }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            if message.isSelf {
                selfLoop
            } else {
                straightArrow
            }
            if let label = message.label {
                // Explicit ink (matching TypeNodeView's member rows) so the label stays
                // readable against the canvas in both light and dark themes.
                Text(label)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(palette.secondaryInk)
                    .position(labelPosition)
            }
        }
    }

    // MARK: Straight arrow between two lifelines

    private var straightArrow: some View {
        let start = CGPoint(x: message.fromX, y: message.y)
        let end = CGPoint(x: message.toX, y: message.y)
        let angle: CGFloat = message.toX >= message.fromX ? 0 : .pi
        return ZStack {
            Path { path in
                path.move(to: start)
                path.addLine(to: end)
            }
            .stroke(color, style: message.kind.sequenceStrokeStyle)

            arrowHead(at: end, angle: angle)
        }
    }

    // MARK: Self-message loop

    private var selfLoop: some View {
        let top = message.y - 6
        let bottom = message.y + 10
        let right = max(message.fromX, message.toX) + SequenceLayoutModel.selfLoopWidth * 0.7
        return ZStack {
            Path { path in
                path.move(to: CGPoint(x: message.fromX, y: top))
                path.addLine(to: CGPoint(x: right, y: top))
                path.addLine(to: CGPoint(x: right, y: bottom))
                path.addLine(to: CGPoint(x: message.toX, y: bottom))
            }
            .stroke(color, style: message.kind.sequenceStrokeStyle)

            arrowHead(at: CGPoint(x: message.toX, y: bottom), angle: .pi)
        }
    }

    @ViewBuilder
    private func arrowHead(at point: CGPoint, angle: CGFloat) -> some View {
        switch message.kind {
        case .synchronous, .create, .destroy:
            // Filled (solid) arrowhead.
            Path.emptyTriangle(at: point, angle: angle, size: 10).fill(color)
        case .asynchronous, .return:
            // Open arrowhead.
            Path.openArrow(at: point, angle: angle, size: 9).stroke(color, lineWidth: 1.5)
        }
    }

    private var labelPosition: CGPoint {
        if message.isSelf {
            let right = max(message.fromX, message.toX) + SequenceLayoutModel.selfLoopWidth * 0.7
            return CGPoint(x: right + 4, y: message.y + 2)
        }
        let midX = (message.fromX + message.toX) / 2
        return CGPoint(x: midX, y: message.y - 9)
    }
}

// MARK: - Styling

extension SequenceDiagram.Message.Kind {
    /// Stroke for a message line: solid for calls, dashed for returns / async fire-and-forget.
    var sequenceStrokeStyle: StrokeStyle {
        switch self {
        case .synchronous, .create:
            StrokeStyle(lineWidth: 1.5)
        case .return, .destroy:
            StrokeStyle(lineWidth: 1.5, dash: [6, 4])
        case .asynchronous:
            StrokeStyle(lineWidth: 1.5, dash: [2, 3])
        }
    }
}
