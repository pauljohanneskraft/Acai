import SwiftUI
import AcaiCore
import AcaiDiagram
import AcaiRender
import UniformTypeIdentifiers

/// Movement-only view for a generated sequence diagram. Regenerates the diagram from its stored
/// entry-point configuration and lets the user slide participant lifelines horizontally; built on
/// the shared canvas layer (`PannableCanvas`, drag gesture, undo/redo) like the class view.
struct SequenceDiagramView: View {
    let diagram: GeneratedDiagram
    let artifact: CodeArtifact
    let codebase: Codebase

    @EnvironmentObject private var model: ProjectBrowserViewModel
    @StateObject private var viewModel: SequenceDiagramViewModel

    @State private var canvasScale: CGFloat
    @State private var canvasOffset: CGPoint
    @State private var dragStartPositions: [String: CGPoint] = [:]
    @State private var activeDragCanvasLocation: CGPoint?
    @State private var canvasAutoPanController = EdgeAutoPanController()
    @State private var canvasViewportSize = CGSize(width: 900, height: 600)
    @State private var showSidebar = false
    @State private var sidebarTab: SequenceDiagramSidebarTab = .settings
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private var isCompactWidth: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    init(diagram: GeneratedDiagram, artifact: CodeArtifact, codebase: Codebase) {
        self.diagram = diagram
        self.artifact = artifact
        self.codebase = codebase
        let config = diagram.sequenceConfiguration
            ?? SequenceDiagramConfiguration(entryTypeName: "", entryMethodName: "")
        self._viewModel = StateObject(wrappedValue: SequenceDiagramViewModel(
            artifact: artifact,
            configuration: config,
            restoredPositions: diagram.nodePositions.mapValues { CGPoint(x: $0.x, y: $0.y) }
        ))
        self._canvasScale = State(initialValue: CGFloat(diagram.canvasScale))
        self._canvasOffset = State(initialValue: CGPoint(x: diagram.canvasOffsetX, y: diagram.canvasOffsetY))
    }

    var body: some View {
        sidebarPresentedCanvas
            .toolbar { toolbarContent }
            .diagramCanvasLifecycle(
                title: diagram.name, model: viewModel, onSave: savePositions, onCenter: centerDiagram
            )
            .userActivity(DiagramHandoffActivity.activityType) {
                DiagramHandoffActivity(diagram: diagram, codebase: codebase).configure($0)
            }
    }

    /// See `ClassDiagramView.sidebarPresentedCanvas`'s doc comment for why compact width (iPhone)
    /// uses a real `.sheet` here instead of relying on `.inspector`'s own collapsed presentation.
    @ViewBuilder
    private var sidebarPresentedCanvas: some View {
        #if os(iOS)
        if isCompactWidth {
            diagramContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .sheet(isPresented: $showSidebar) {
                    NavigationStack {
                        sidebar
                            .navigationTitle(diagram.name)
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button(.app("View.SequenceDiagramView.Done")) { showSidebar = false }
                                        .accessibilityIdentifier("diagram.sidebarDoneButton")
                                }
                            }
                    }
                }
        } else {
            diagramContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .inspector(isPresented: $showSidebar) {
                    sidebar
                        .inspectorColumnWidth(min: 240, ideal: 300, max: 380)
                }
        }
        #else
        diagramContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .inspector(isPresented: $showSidebar) {
                sidebar
                    .inspectorColumnWidth(min: 240, ideal: 300, max: 380)
            }
        #endif
    }

    /// The config-sheet fields fold into the Settings tab (live draft + Apply, not a modal);
    /// Save as Freeform/Export Image move here from the toolbar.
    private var sidebar: SequenceDiagramSidebar {
        SequenceDiagramSidebar(
            viewModel: viewModel, artifact: artifact, codebaseID: codebase.id, tab: $sidebarTab,
            onApply: { config in
                viewModel.applyConfiguration(config)
                model.diagrams.updateSequenceConfiguration(diagramID: diagram.id, configuration: config)
                centerDiagram()
            },
            onApplyFilter: { filter in
                viewModel.applyFilter(filter)
                model.diagrams.updateSequenceFilter(diagramID: diagram.id, filter: filter)
            },
            onSaveAsFreeform: {
                // Pass every participant's live x (not just dragged overrides) so the freeform
                // copy reproduces the current layout exactly.
                let layoutPositions = Dictionary(
                    viewModel.layout.participants.map { ($0.id, CGPoint(x: $0.lifelineX, y: 0)) },
                    uniquingKeysWith: { first, _ in first }
                )
                model.saveAsFreeformDiagram(
                    id: diagram.id,
                    positions: layoutPositions,
                    scale: canvasScale,
                    offset: canvasOffset
                )
            },
            onExportImage: exportImage
        )
    }

    private var diagramContent: some View {
        Group {
            if viewModel.isEmpty {
                emptyState
            } else {
                canvasContent
            }
        }
    }

    // MARK: - Canvas

    private var canvasContent: some View {
        PannableCanvas(
            model: viewModel,
            scale: $canvasScale,
            offset: $canvasOffset,
            activeDragCanvasLocation: activeDragCanvasLocation,
            autoPanController: canvasAutoPanController,
            onViewportSizeChange: { canvasViewportSize = $0 },
            content: {
                let layout = viewModel.layout
                ZStack(alignment: .topLeading) {
                    SequenceEnsembleView(layout: layout)
                    ForEach(layout.participants) { participant in
                        participantHeader(participant)
                    }
                    ForEach(layout.messages) { message in
                        messageTapTarget(message)
                    }
                }
            }
        )
    }

    private func participantHeader(_ participant: SequenceLayoutModel.ParticipantFrame) -> some View {
        SequenceParticipantHeader(
            participant: participant,
            isSelected: viewModel.selectedNodeIDs.contains(participant.id)
        )
        .frame(width: participant.headerRect.width, height: participant.headerRect.height)
        .position(x: participant.headerRect.midX, y: participant.headerRect.midY)
        .onTapGesture(count: 2) {
            viewModel.selectNode(participant.id, extending: false)
            sidebarTab = .inspector
            showSidebar = true
        }
        .diagramNodeInteraction(
            id: participant.id,
            model: viewModel,
            dragStartPositions: $dragStartPositions,
            activeDragCanvasLocation: $activeDragCanvasLocation,
            onCommit: savePositions
        )
    }

    /// An invisible tap strip over a message arrow, selecting it for the Inspector tab — mirrors
    /// `FreeformDiagramView+Canvas.swift`'s `messageTapTarget`, but sized to a full 44pt tall hit area
    /// (Freeform's 30pt strip is a tap-target shortfall this doesn't repeat).
    private func messageTapTarget(_ message: SequenceLayoutModel.MessageLayout) -> some View {
        let width = max(abs(message.toX - message.fromX), 44)
        let midX = (message.fromX + message.toX) / 2
        let isSelected = viewModel.selectedMessageID == message.id
        return RoundedRectangle(cornerRadius: 4)
            .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
            #if os(macOS)
            .cursorOnHover(.pointingHand)
            #endif
            .frame(width: width + 16, height: 44)
            .position(x: midX, y: message.y)
            .accessibilityElement()
            .accessibilityLabel(messageAccessibilityLabel(message))
            .accessibilityAddTraits(.isButton)
            .onTapGesture(count: 2) {
                viewModel.clearSelection()
                viewModel.selectedMessageID = message.id
                sidebarTab = .inspector
                showSidebar = true
            }
            .onTapGesture(count: 1) {
                let newSelection = (viewModel.selectedMessageID == message.id) ? nil : message.id
                viewModel.clearSelection()
                viewModel.selectedMessageID = newSelection
            }
    }

    private func messageAccessibilityLabel(_ message: SequenceLayoutModel.MessageLayout) -> String {
        "Message" + (message.label.map { ": \($0)" } ?? "")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            UndoRedoToolbarButtons(model: viewModel, onChange: savePositions)
            #if !os(macOS)
            MultiSelectToggleButton(model: viewModel)
            #endif

            Button {
                centerDiagram()
            } label: {
                Label(.app("View.SequenceDiagramView.FitView"), systemImage: "rectangle.dashed")
            }
            .help(.app("View.SequenceDiagramView.FitDiagramVisibleCanvas"))
            .keyboardShortcut("0", modifiers: .command)
            .accessibilityIdentifier("diagram.fitToViewButton")
            Button {
                showSidebar.toggle()
            } label: {
                Label(.app("View.SequenceDiagramView.Sidebar"), systemImage: "sidebar.trailing")
            }
            .help(.app("View.SequenceDiagramView.ToggleSidebar"))
            .accessibilityIdentifier("diagram.sidebarToggleButton")
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(.app("View.SequenceDiagramView.NoCallsCouldTraced"))
                .foregroundStyle(.secondary)
            Text(.app("View.SequenceDiagramView.CallsAreFollowedThrough"))
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button {
                sidebarTab = .settings
                showSidebar = true
            } label: {
                Label(.app("View.SequenceDiagramView.EditConfiguration"), systemImage: "slider.horizontal.3")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Persistence & layout

    private func savePositions() {
        model.diagrams.updatePositions(
            diagramID: diagram.id,
            positions: viewModel.positionOverrides,
            scale: canvasScale,
            offset: canvasOffset
        )
    }

    /// `FitToView` unions whatever rects it's handed, so header rects alone would center just the
    /// ~44pt header strip and push messages/activation bars/fragments below vertical center.
    /// `layout.contentSize` (anchored at the same origin `SequenceEnsembleView` renders from) covers
    /// the vertical extent; the header rects stay in the union too, since a dragged header left of
    /// the layout's default origin isn't captured by `contentSize`'s own width.
    private func centerDiagram() {
        let layout = viewModel.layout
        let headerIDs = layout.participants.map(\.id)
        guard let headerUnion = headerIDs
            .compactMap({ viewModel.nodeRect($0) })
            .reduce(into: CGRect?.none, { $0 = $0?.union($1) ?? $1 })
        else { return }
        let fullExtent = headerUnion.union(CGRect(origin: .zero, size: layout.contentSize))
        guard let fit = FitToView(
            nodeIDs: ["sequenceDiagram.fullExtent"],
            rect: { _ in fullExtent },
            viewport: canvasViewportSize
        ).transform else { return }
        canvasScale = fit.scale
        canvasOffset = fit.offset
        savePositions()
    }

    private func exportImage() {
        model.exportImage(named: diagram.name, using: viewModel)
    }
}
