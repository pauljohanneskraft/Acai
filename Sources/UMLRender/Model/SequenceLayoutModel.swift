import CoreGraphics
import Foundation
import UMLDiagram

/// Pure, headless-friendly layout for a `SequenceDiagram`: turns participants and
/// time-ordered messages into concrete geometry (header rects, vertical lifelines,
/// horizontal message arrows and execution-occurrence bars). Shared by the live app canvas,
/// the custom-diagram editor and the CLI image export, so all draw identical diagrams —
/// mirroring how `DiagramLayoutModel` backs the class diagram.
///
/// Coordinates originate at `(0, 0)` (top-left of the header row). Participants are placed
/// left-to-right in their generated order; a caller may override a participant's horizontal
/// centre (keyed by `Participant.id`) to spread lifelines apart, which is the only layout
/// editing the generated sequence view allows.
public struct SequenceLayoutModel {

    // MARK: - Tunables

    /// Vertical extent of a participant header box.
    public static let headerHeight: CGFloat = 44
    /// Horizontal gap between the edges of adjacent participant headers.
    public static let participantGap: CGFloat = 64
    /// Vertical gap between the header row and the first message.
    public static let firstMessageGap: CGFloat = 36
    /// Vertical distance between consecutive messages.
    public static let messageRowHeight: CGFloat = 44
    /// Slack drawn below the last message before the lifeline ends.
    public static let lifelineTailGap: CGFloat = 28
    /// Width reserved for a self-message loop.
    public static let selfLoopWidth: CGFloat = 56
    /// Width of an execution-occurrence (activation) bar.
    public static let activationWidth: CGFloat = 10
    /// Horizontal offset of each nesting level of activation bars.
    public static let activationNestOffset: CGFloat = 5
    /// Vertical lead/tail an activation bar extends past its first/last message.
    public static let activationCap: CGFloat = 8
    /// Extra vertical space inserted before a row that opens a fragment operand, making room
    /// for the operator tab, guard label and operand separator without overlapping messages.
    public static let fragmentLeadIn: CGFloat = 36

    // MARK: - Geometry

    public struct ParticipantFrame: Identifiable, Sendable {
        public let id: String
        public let name: String
        public let kind: SequenceDiagram.Participant.Kind
        /// Header box, with `midX` sitting on the lifeline.
        public let headerRect: CGRect
        public let lifelineTop: CGFloat
        public let lifelineBottom: CGFloat

        public var lifelineX: CGFloat { headerRect.midX }
    }

    public struct MessageLayout: Identifiable, Sendable {
        public let id: Int
        /// Arrow start x — the edge of the sender's activation bar (or its lifeline).
        public let fromX: CGFloat
        /// Arrow end x — the edge of the receiver's activation bar (or its lifeline).
        public let toX: CGFloat
        public let y: CGFloat
        public let label: String?
        public let kind: SequenceDiagram.Message.Kind
        /// Whether sender and receiver are the same lifeline (drawn as a loop).
        public let isSelf: Bool

        public init(
            id: Int,
            fromX: CGFloat,
            toX: CGFloat,
            y: CGFloat,
            label: String?,
            kind: SequenceDiagram.Message.Kind,
            isSelf: Bool = false
        ) {
            self.id = id
            self.fromX = fromX
            self.toX = toX
            self.y = y
            self.label = label
            self.kind = kind
            self.isSelf = isSelf
        }
    }

    /// An execution occurrence ("focus of control"): the thin rectangle on a lifeline marking
    /// the span during which the participant is active.
    public struct ActivationBar: Identifiable, Sendable {
        public let id: Int
        public let participantID: String
        public let rect: CGRect
    }

    /// A laid-out combined fragment: the frame around its covered message rows, plus the y of
    /// each operand separator and the guard label for each operand.
    public struct FragmentFrame: Identifiable, Sendable {
        public let id: String
        public let kind: SequenceDiagram.Fragment.Kind
        public let rect: CGRect
        /// y positions of the dashed separators between operands (empty for single-operand).
        public let separatorYs: [CGFloat]
        /// Guard labels with the y of the operand they belong to (just below its top edge).
        public let guards: [(label: String, y: CGFloat)]
    }

    public let participants: [ParticipantFrame]
    public let messages: [MessageLayout]
    public let activations: [ActivationBar]
    public let fragments: [FragmentFrame]
    public let contentSize: CGSize

    // MARK: - Init

    /// - Parameters:
    ///   - diagram: The generated sequence diagram.
    ///   - positionOverrides: Optional horizontal-centre overrides keyed by `Participant.id`.
    public init(diagram: SequenceDiagram, positionOverrides: [String: CGFloat] = [:]) {
        let ordered = diagram.messages.sorted { $0.order < $1.order }
        let messageAreaTop = Self.headerHeight + Self.firstMessageGap
        let (yByOrder, rowsBottom) = Self.rowYs(for: ordered, fragments: diagram.fragments, top: messageAreaTop)
        let lifelineBottom = rowsBottom + Self.lifelineTailGap

        // Place headers left-to-right, honouring per-participant width and overrides. Each
        // participant keeps a stable *default* slot; an override moves only that header, leaving
        // its neighbours' slots untouched (so dragging one lifeline doesn't drag the rest).
        var frames: [ParticipantFrame] = []
        var frameByName: [String: ParticipantFrame] = [:]
        var defaultRightEdge: CGFloat = 0  // right edge of the previous *default* slot
        for participant in diagram.participants {
            let width = Self.headerWidth(for: participant.name)
            let defaultCentre = defaultRightEdge + (frames.isEmpty ? 0 : Self.participantGap) + width / 2
            defaultRightEdge = defaultCentre + width / 2
            let centre = positionOverrides[participant.id] ?? defaultCentre
            let headerRect = CGRect(
                x: centre - width / 2, y: 0,
                width: width, height: Self.headerHeight
            )
            let frame = ParticipantFrame(
                id: participant.id,
                name: participant.name,
                kind: participant.kind,
                headerRect: headerRect,
                lifelineTop: Self.headerHeight,
                lifelineBottom: lifelineBottom
            )
            frames.append(frame)
            frameByName[participant.name] = frame
        }
        self.participants = frames

        // Lay out messages top-to-bottom while tracking execution occurrences: a call pushes an
        // activation on the receiver, the matching return pops it. Arrow endpoints sit on the
        // edges of the active bars so arrows visibly connect activations (UML 2 notation).
        // Endpoints resolve by participant *name*, because the generator records
        // `Message.from`/`to` as type names (while `Participant.id` is the type id).
        var pass = ActivationPass(frameByName: frameByName)

        // The initiating participant gets an implicit root activation: it is "executing" for the
        // whole interaction even though no message ever activates it.
        if let first = ordered.first, frameByName[first.from] != nil {
            pass.push(on: first.from, at: (yByOrder[first.order] ?? messageAreaTop) - Self.activationCap)
        }

        for (index, message) in ordered.enumerated() {
            pass.layOut(message: message, index: index, y: yByOrder[message.order] ?? messageAreaTop)
        }
        let lastY = ordered.last.flatMap { yByOrder[$0.order] } ?? messageAreaTop
        pass.closeRemaining(at: lastY + Self.activationCap)

        self.messages = pass.messages
        self.activations = pass.bars

        // Combined fragments: frame each one around the rows of the messages it covers. Larger
        // (outer) fragments first so nested fragments draw on top.
        self.fragments = diagram.fragments
            .compactMap { Self.fragmentFrame($0, yByOrder: yByOrder, messages: ordered, frameByName: frameByName) }
            .sorted { $0.rect.width * $0.rect.height > $1.rect.width * $1.rect.height }

        let headerMaxX = frames.map(\.headerRect.maxX).max() ?? Self.headerWidth(for: diagram.title ?? "")
        let fragmentMaxX = self.fragments.map(\.rect.maxX).max() ?? 0
        // Reserve room for a self-loop hanging off the right-most lifeline.
        let width = max(headerMaxX + Self.selfLoopWidth, fragmentMaxX + 8)
        self.contentSize = CGSize(width: width, height: lifelineBottom)
    }

    /// Assigns each message its row y (top-to-bottom by order), inserting extra lead-in before
    /// rows that open a fragment operand so the operator tab, guard and separator have their own
    /// vertical space instead of overlapping message labels. Returns the y per message order and
    /// the bottom of the last row.
    private static func rowYs(
        for ordered: [SequenceDiagram.Message],
        fragments: [SequenceDiagram.Fragment],
        top: CGFloat
    ) -> (yByOrder: [Int: CGFloat], bottom: CGFloat) {
        var leadInBefore: [Int: CGFloat] = [:]
        for fragment in fragments {
            for operand in fragment.operands {
                leadInBefore[operand.firstOrder, default: 0] += Self.fragmentLeadIn
            }
        }
        var yByOrder: [Int: CGFloat] = [:]
        var nextY = top
        for message in ordered {
            nextY += leadInBefore[message.order] ?? 0
            yByOrder[message.order] = nextY
            nextY += Self.messageRowHeight
        }
        return (yByOrder, max(nextY, top + Self.messageRowHeight))
    }

    /// Lays out one combined fragment, or `nil` when none of its operands cover any laid-out
    /// message (fragments are anchored to message rows, not free-floating).
    private static func fragmentFrame(
        _ fragment: SequenceDiagram.Fragment,
        yByOrder: [Int: CGFloat],
        messages: [SequenceDiagram.Message],
        frameByName: [String: ParticipantFrame]
    ) -> FragmentFrame? {
        let operands = fragment.operands.sorted { $0.firstOrder < $1.firstOrder }

        // Per-operand vertical span from its covered message rows, plus the lifelines involved.
        var spans: [(operand: SequenceDiagram.Fragment.Operand, minY: CGFloat, maxY: CGFloat)] = []
        var coveredNames: Set<String> = []
        var coversSelfMessage = false
        for operand in operands {
            let covered = messages.filter { $0.order >= operand.firstOrder && $0.order <= operand.lastOrder }
            let rowYs = covered.compactMap { yByOrder[$0.order] }
            guard let minY = rowYs.min(), let maxY = rowYs.max() else { continue }
            spans.append((operand, minY, maxY))
            for message in covered {
                coveredNames.insert(message.from)
                coveredNames.insert(message.to)
                if message.from == message.to { coversSelfMessage = true }
            }
        }
        guard let firstSpan = spans.first, let lastSpan = spans.last else { return nil }

        let lifelineXs = coveredNames.compactMap { frameByName[$0]?.lifelineX }
        guard let minLifelineX = lifelineXs.min(), let maxLifelineX = lifelineXs.max() else { return nil }
        let horizontalPad: CGFloat = 36
        let left = minLifelineX - horizontalPad
        let right = maxLifelineX + horizontalPad + (coversSelfMessage ? Self.selfLoopWidth * 0.7 : 0)

        // The lead-in inserted before each operand's first row hosts the tab, guard and
        // separator; a little slack below the last covered row.
        let top = firstSpan.minY - Self.fragmentLeadIn + 2
        let rect = CGRect(
            x: left, y: top,
            width: right - left, height: (lastSpan.maxY + 14) - top
        )
        let separatorYs = spans.dropFirst().map { $0.minY - Self.fragmentLeadIn + 4 }
        let guards: [(label: String, y: CGFloat)] = spans.compactMap { span in
            guard let label = span.operand.guardLabel, !label.isEmpty else { return nil }
            return ("[\(label)]", span.minY - 20)
        }
        return FragmentFrame(
            id: fragment.id, kind: fragment.kind, rect: rect,
            separatorYs: separatorYs, guards: guards
        )
    }

    // MARK: - Helpers

    /// Estimated header width for a participant name (no SwiftUI measurement headlessly).
    public static func headerWidth(for name: String) -> CGFloat {
        // ~8pt per character (13pt semibold monospaced) plus horizontal padding, clamped to a
        // sensible range.
        let estimated = CGFloat(name.count) * 8 + 32
        return min(max(estimated, 96), 300)
    }
}

// MARK: - Activation tracking

/// Mutable state for the message/activation layout pass: a stack of open activation bars per
/// participant, the finished bars, and the laid-out messages with bar-edge arrow endpoints.
private struct ActivationPass {
    let frameByName: [String: SequenceLayoutModel.ParticipantFrame]

    private(set) var messages: [SequenceLayoutModel.MessageLayout] = []
    private(set) var bars: [SequenceLayoutModel.ActivationBar] = []
    /// Open activations per participant name: the y where each began, bottom of stack first.
    private var open: [String: [CGFloat]] = [:]
    private var barID = 0

    init(frameByName: [String: SequenceLayoutModel.ParticipantFrame]) {
        self.frameByName = frameByName
    }

    /// Centre x of the top activation bar on a participant (its lifeline when none is open).
    private func topBarCentreX(_ name: String) -> CGFloat {
        guard let frame = frameByName[name] else { return 0 }
        let depth = open[name]?.count ?? 0
        guard depth > 0 else { return frame.lifelineX }
        return frame.lifelineX + CGFloat(depth - 1) * SequenceLayoutModel.activationNestOffset
    }

    mutating func push(on name: String, at y: CGFloat) {
        open[name, default: []].append(y)
    }

    /// Pop the top activation of a participant, emitting its finished bar.
    private mutating func pop(on name: String, at y: CGFloat) {
        guard let frame = frameByName[name], var stack = open[name], !stack.isEmpty else { return }
        let start = stack.removeLast()
        open[name] = stack
        let centre = frame.lifelineX + CGFloat(stack.count) * SequenceLayoutModel.activationNestOffset
        bars.append(SequenceLayoutModel.ActivationBar(
            id: barID,
            participantID: frame.id,
            rect: CGRect(
                x: centre - SequenceLayoutModel.activationWidth / 2,
                y: start,
                width: SequenceLayoutModel.activationWidth,
                height: max(y - start, SequenceLayoutModel.activationWidth)
            )
        ))
        barID += 1
    }

    /// Close every still-open activation (e.g. async calls without returns, the root activation).
    mutating func closeRemaining(at y: CGFloat) {
        for name in open.keys.sorted() {
            while !(open[name]?.isEmpty ?? true) {
                pop(on: name, at: y)
            }
        }
    }

    mutating func layOut(message: SequenceDiagram.Message, index: Int, y: CGFloat) {
        guard
            let from = frameByName[message.from],
            let to = frameByName[message.to]
        else { return }
        let half = SequenceLayoutModel.activationWidth / 2
        let isSelf = message.from == message.to

        let fromX: CGFloat
        let toX: CGFloat
        if message.kind == .return {
            // The returner's activation ends here; the arrow leaves its bar edge.
            let sourceCentre = topBarCentreX(message.from)
            pop(on: message.from, at: y + SequenceLayoutModel.activationCap)
            let targetCentre = topBarCentreX(message.to)
            let direction: CGFloat = to.lifelineX >= from.lifelineX ? 1 : -1
            fromX = sourceCentre + direction * half
            toX = isSelf ? targetCentre + half : targetCentre - direction * half
        } else {
            // A call leaves the sender's current bar and opens a new activation on the receiver.
            let sourceCentre = topBarCentreX(message.from)
            push(on: message.to, at: y - SequenceLayoutModel.activationCap)
            let targetCentre = topBarCentreX(message.to)
            let direction: CGFloat = isSelf ? 1 : (to.lifelineX >= from.lifelineX ? 1 : -1)
            fromX = sourceCentre + direction * half
            toX = isSelf ? targetCentre + half : targetCentre - direction * half
        }

        messages.append(SequenceLayoutModel.MessageLayout(
            id: index,
            fromX: fromX,
            toX: toX,
            y: y,
            label: message.label,
            kind: message.kind,
            isSelf: isSelf
        ))
    }
}
