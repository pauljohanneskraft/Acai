import SwiftUI
import UMLRender

/// A reusable infinite canvas container that supports pan (trackpad), zoom (scroll wheel / pinch),
/// a selection rectangle (click-drag), and edge auto-panning during node drags.
///
/// ## Auto-Pan
/// The *caller* owns the `EdgeAutoPanController` (as `@State`) and passes it in.
/// During a drag gesture the caller sets `autoPanDragLocation` and reads
/// `autoPanController.accumulatedCanvasDelta` to keep nodes glued to the cursor.
struct InfiniteCanvas<Content: View>: View {
    @Binding var scale: CGFloat
    @Binding var offset: CGPoint

    /// Called when user finishes a selection-rectangle drag on the background.
    /// The rectangle is in canvas coordinates (pre-scale, pre-offset).
    var onSelectionRect: ((CGRect) -> Void)?

    /// Called when the user taps the empty canvas background (no drag).
    var onBackgroundTap: (() -> Void)?

    /// Canvas-space location of an active node drag, or `nil` when idle.
    /// Setting this to a non-nil value activates edge auto-panning.
    var autoPanDragLocation: CGPoint?

    /// Called each auto-pan tick with the *incremental* canvas delta.
    /// Use this to move all selected nodes by the delta (the timer keeps
    /// firing even when the cursor doesn't move).
    var onAutoPanDelta: ((CGSize) -> Void)?

    /// The auto-pan controller, owned by the parent view as `@State`.
    var autoPanController: EdgeAutoPanController

    @State private var selectionStart: CGPoint?
    @State private var selectionCurrent: CGPoint?

    @Environment(\.diagramPalette) private var palette

    let content: () -> Content

    init(
        scale: Binding<CGFloat>,
        offset: Binding<CGPoint>,
        onSelectionRect: ((CGRect) -> Void)? = nil,
        onBackgroundTap: (() -> Void)? = nil,
        autoPanDragLocation: CGPoint? = nil,
        onAutoPanDelta: ((CGSize) -> Void)? = nil,
        autoPanController: EdgeAutoPanController = EdgeAutoPanController(),
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._scale = scale
        self._offset = offset
        self.onSelectionRect = onSelectionRect
        self.onBackgroundTap = onBackgroundTap
        self.autoPanDragLocation = autoPanDragLocation
        self.onAutoPanDelta = onAutoPanDelta
        self.autoPanController = autoPanController
        self.content = content
    }

    var body: some View {
        GeometryReader { geometry in
            // swiftlint:disable:next redundant_discardable_let
            let _ = configureAutoPan(viewportSize: geometry.size)
            ZStack {
                // Grid background layer.
                CanvasGridBackground(scale: scale, offset: offset)

                // Transformed content layer.
                content()
                    .scaleEffect(scale, anchor: .topLeading)
                    .offset(x: offset.x, y: offset.y)

                // Selection rectangle overlay (screen coordinates).
                selectionRectOverlay
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .background(palette.canvasBackground)
            .gesture(selectionGesture)
            .onTapGesture {
                onBackgroundTap?()
            }
            #if os(macOS)
            .overlay(ScrollWheelZoomHandler(scale: $scale, offset: $offset))
            #endif
        }
    }

    // MARK: - Auto-Pan Configuration

    /// Called every body evaluation to keep the auto-pan controller in sync.
    private func configureAutoPan(viewportSize: CGSize) {
        autoPanController.scale = scale
        autoPanController.offset = offset
        autoPanController.viewportSize = viewportSize

        autoPanController.onPanTick = { canvasDelta in
            offset.x -= canvasDelta.width * scale
            offset.y -= canvasDelta.height * scale
            onAutoPanDelta?(canvasDelta)
        }

        if let loc = autoPanDragLocation {
            autoPanController.canvasLocation = loc
            if !autoPanController.isRunning { autoPanController.start() }
        } else {
            autoPanController.stop()
        }
    }

    // MARK: - Selection Rectangle Gesture

    /// Click-drag on the canvas background draws a selection rectangle.
    /// Panning is handled by the trackpad / scroll wheel event monitors.
    private var selectionGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if selectionStart == nil {
                    selectionStart = value.startLocation
                }
                selectionCurrent = value.location
            }
            .onEnded { _ in
                if let start = selectionStart, let end = selectionCurrent {
                    // Convert screen coordinates to canvas coordinates.
                    let canvasStart = screenToCanvas(start)
                    let canvasEnd = screenToCanvas(end)
                    let rect = CGRect(
                        x: min(canvasStart.x, canvasEnd.x),
                        y: min(canvasStart.y, canvasEnd.y),
                        width: abs(canvasEnd.x - canvasStart.x),
                        height: abs(canvasEnd.y - canvasStart.y)
                    )
                    onSelectionRect?(rect)
                }
                selectionStart = nil
                selectionCurrent = nil
            }
    }

    @ViewBuilder
    private var selectionRectOverlay: some View {
        if let start = selectionStart, let current = selectionCurrent {
            let rect = CGRect(
                x: min(start.x, current.x),
                y: min(start.y, current.y),
                width: abs(current.x - start.x),
                height: abs(current.y - start.y)
            )
            Rectangle()
                .stroke(Color.accentColor.opacity(0.8), lineWidth: 1)
                .background(Color.accentColor.opacity(0.08))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
    }

    // MARK: - Coordinate Conversion

    private func screenToCanvas(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - offset.x) / scale,
            y: (point.y - offset.y) / scale
        )
    }
}
