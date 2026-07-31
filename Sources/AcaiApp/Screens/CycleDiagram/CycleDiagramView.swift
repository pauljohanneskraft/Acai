import SwiftUI
import AcaiCore

/// Read-only analysis view: isolates and renders exactly one detected `AcaiQuality
/// .CycleFinder` cycle's members and the edges connecting them, laid out as the loop it is —
/// members placed evenly around a circle, arrows drawn between the ones a relationship actually
/// connects. No new detection logic (`CycleDiagramData` only resolves display edges among an
/// already-known member set); no drag/undo/redo/Save-as-Freeform/Export (see
/// `GeneratedDiagram+Freeform.swift`'s doc comment) — a fixed, auto-fit layout since there is
/// nothing to arrange.
///
/// Every custom-drawn node/edge gets an explicit accessibility representation: each node bubble is
/// its own accessibility element with a label, and the edge list restates every connection as
/// text (`"A → B"`) for anyone not looking at the canvas.
struct CycleDiagramView: View {
    let diagram: GeneratedDiagram
    let codebase: Codebase
    private let data: CycleDiagramData

    @State private var showSidebar = false
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    init(diagram: GeneratedDiagram, artifact: CodeArtifact, codebase: Codebase) {
        self.diagram = diagram
        self.codebase = codebase
        let reference = diagram.cycleDiagramReference ?? CycleDiagramReference(scope: "types", members: [])
        self.data = CycleDiagramData(reference: reference, artifact: artifact)
    }

    private var isCompactWidth: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    var body: some View {
        sidebarPresentedContent
            .navigationTitle(diagram.name)
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
    }

    @ViewBuilder
    private var sidebarPresentedContent: some View {
        #if os(iOS)
        if isCompactWidth {
            loopContent
                .sheet(isPresented: $showSidebar) {
                    NavigationStack {
                        edgeList
                            .navigationTitle("Cycle Members")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") { showSidebar = false }
                                        .accessibilityIdentifier("diagram.sidebarDoneButton")
                                }
                            }
                    }
                }
        } else {
            loopContent
                .inspector(isPresented: $showSidebar) {
                    edgeList.inspectorColumnWidth(min: 240, ideal: 300, max: 380)
                }
        }
        #else
        loopContent
            .inspector(isPresented: $showSidebar) {
                edgeList.inspectorColumnWidth(min: 240, ideal: 300, max: 380)
            }
        #endif
    }

    // MARK: - Loop layout

    @ViewBuilder
    private var loopContent: some View {
        if data.nodes.isEmpty {
            emptyState
        } else {
            GeometryReader { proxy in
                let layout = CycleLoopLayout(nodeCount: data.nodes.count, viewportSize: proxy.size)
                ZStack {
                    ForEach(data.edges) { edge in
                        if let fromIndex = data.nodes.firstIndex(where: { $0.id == edge.from }),
                           let toIndex = data.nodes.firstIndex(where: { $0.id == edge.to }) {
                            CycleEdgeShape(
                                from: layout.position(at: fromIndex), to: layout.position(at: toIndex),
                                nodeRadius: layout.nodeRadius
                            )
                            .stroke(Color.secondary, lineWidth: 2)
                        }
                    }
                    ForEach(Array(data.nodes.enumerated()), id: \.element.id) { index, node in
                        cycleNodeBubble(node, radius: layout.nodeRadius)
                            .position(layout.position(at: index))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal").font(.system(size: 28)).foregroundStyle(.secondary)
            Text("This cycle no longer has any members — it may have been resolved since this "
                 + "diagram was created. Reindexing the codebase and reopening the Quality Check "
                 + "report will confirm.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func cycleNodeBubble(_ node: CycleDiagramData.Node, radius: CGFloat) -> some View {
        Text(node.label)
            .font(.caption.bold())
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(8)
            .frame(width: radius * 2, height: radius * 2)
            .background(Circle().fill(Color.accentColor.opacity(0.15)))
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(node.label)
            .accessibilityAddTraits(.isStaticText)
    }

    // MARK: - Sidebar (member/edge list — the non-visual, accessible restatement of the loop)

    private var edgeList: some View {
        List {
            Section("Members (\(data.nodes.count))") {
                ForEach(data.nodes) { node in
                    Text(node.label).font(.callout)
                }
            }
            Section("Dependencies (\(data.edges.count))") {
                ForEach(data.edges) { edge in
                    let fromLabel = data.nodes.first { $0.id == edge.from }?.label ?? edge.from
                    let toLabel = data.nodes.first { $0.id == edge.to }?.label ?? edge.to
                    Text("\(fromLabel) → \(toLabel)")
                        .font(.caption.monospaced())
                }
            }
        }
        #if os(macOS)
        .listStyle(.inset)
        #endif
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                showSidebar.toggle()
            } label: {
                Label("Sidebar", systemImage: "sidebar.trailing")
            }
            .help("Toggle the member/dependency list")
            .accessibilityIdentifier("diagram.sidebarToggleButton")
        }
    }
}

/// Places `nodeCount` points evenly around a circle inscribed in `viewportSize`, leaving room for
/// each node's own radius so bubbles never clip the frame edge.
private struct CycleLoopLayout {
    let nodeCount: Int
    let viewportSize: CGSize

    var nodeRadius: CGFloat { 36 }

    private var center: CGPoint { CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2) }

    private var radius: CGFloat {
        max(40, min(viewportSize.width, viewportSize.height) / 2 - nodeRadius - 24)
    }

    func position(at index: Int) -> CGPoint {
        guard nodeCount > 0 else { return center }
        let angle = (2 * Double.pi * Double(index) / Double(nodeCount)) - .pi / 2
        return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }
}

/// A straight arrow between two node centers, trimmed back by `nodeRadius` at each end so the line
/// meets the bubble's edge rather than running through its center/label.
private struct CycleEdgeShape: Shape {
    let from: CGPoint
    let to: CGPoint
    let nodeRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let distance = max(1, (dx * dx + dy * dy).squareRoot())
        let unitX = dx / distance
        let unitY = dy / distance
        let start = CGPoint(x: from.x + unitX * nodeRadius, y: from.y + unitY * nodeRadius)
        let end = CGPoint(x: to.x - unitX * nodeRadius, y: to.y - unitY * nodeRadius)

        var path = Path()
        path.move(to: start)
        path.addLine(to: end)

        let arrowLength: CGFloat = 8
        let arrowAngle: CGFloat = .pi / 7
        let lineAngle = atan2(unitY, unitX)
        path.move(to: end)
        path.addLine(to: CGPoint(
            x: end.x - arrowLength * cos(lineAngle - arrowAngle),
            y: end.y - arrowLength * sin(lineAngle - arrowAngle)))
        path.move(to: end)
        path.addLine(to: CGPoint(
            x: end.x - arrowLength * cos(lineAngle + arrowAngle),
            y: end.y - arrowLength * sin(lineAngle + arrowAngle)))
        return path
    }
}
