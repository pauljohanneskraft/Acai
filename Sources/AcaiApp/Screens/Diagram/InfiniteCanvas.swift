import SwiftUI
import AcaiRender

/// A reusable infinite canvas container that supports pan (trackpad), zoom (scroll wheel / pinch),
/// a selection rectangle (click-drag), and edge auto-panning during node drags. The caller owns
/// the `EdgeAutoPanController` (as `@State`) and passes it in.
struct InfiniteCanvas<Content: View>: View {
    @Binding var scale: CGFloat
    @Binding var offset: CGPoint

    /// The rectangle is in canvas coordinates (pre-scale, pre-offset).
    var onSelectionRect: ((CGRect) -> Void)?

    var onBackgroundTap: (() -> Void)?

    /// Canvas-space. Setting this to a non-nil value activates edge auto-panning.
    var autoPanDragLocation: CGPoint?

    /// Called each auto-pan tick with the *incremental* canvas delta — the timer keeps firing
    /// even when the cursor doesn't move.
    var onAutoPanDelta: ((CGSize) -> Void)?

    var autoPanController: EdgeAutoPanController

    /// Reports the real, measured canvas viewport size whenever it changes, so callers (e.g. a
    /// "fit to view" action) can frame content against the actual visible area instead of an
    /// assumed constant.
    var onViewportSizeChange: ((CGSize) -> Void)?

    @State private var selectionStart: CGPoint?
    @State private var selectionCurrent: CGPoint?
    #if !os(macOS)
    @State private var panStartOffset: CGPoint?
    @State private var magnifyStartScale: CGFloat?
    #endif

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
        onViewportSizeChange: ((CGSize) -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._scale = scale
        self._offset = offset
        self.onSelectionRect = onSelectionRect
        self.onBackgroundTap = onBackgroundTap
        self.autoPanDragLocation = autoPanDragLocation
        self.onAutoPanDelta = onAutoPanDelta
        self.autoPanController = autoPanController
        self.onViewportSizeChange = onViewportSizeChange
        self.content = content
    }

    var body: some View {
        GeometryReader { geometry in
            // swiftlint:disable:next redundant_discardable_let
            let _ = configureAutoPan(viewportSize: geometry.size)
            ZStack {
                CanvasGridBackground(scale: scale, offset: offset)

                content()
                    .scaleEffect(scale, anchor: .topLeading)
                    .offset(x: offset.x, y: offset.y)

                selectionRectOverlay
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .background(palette.canvasBackground)
            #if os(macOS)
            .gesture(selectionGesture)
            #else
            // No trackpad-scroll input on iOS: one-finger drag pans and pinch zooms instead.
            // Marquee selection-by-drag isn't wired up here (no touch equivalent yet).
            .gesture(panGesture)
            .simultaneousGesture(magnificationGesture)
            #endif
            .onTapGesture {
                onBackgroundTap?()
            }
            #if os(macOS)
            .overlay(ScrollWheelZoomHandler(scale: $scale, offset: $offset))
            #endif
            .onAppear { onViewportSizeChange?(geometry.size) }
            .onChange(of: geometry.size) { _, newSize in onViewportSizeChange?(newSize) }
        }
        .overlay(alignment: .bottomTrailing) { zoomIndicator }
    }

    private var zoomIndicator: some View {
        Text(.app("View.InfiniteCanvas.ZoomPercent \(Int((scale * 100).rounded()))"))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .padding(10)
            .allowsHitTesting(false)
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

    /// Panning is handled by the trackpad / scroll wheel event monitors, not here.
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

    #if !os(macOS)

    // MARK: - Touch Pan & Zoom (iOS)

    /// One-finger drag, matching the macOS trackpad two-finger pan.
    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if panStartOffset == nil { panStartOffset = offset }
                guard let start = panStartOffset else { return }
                offset = CGPoint(x: start.x + value.translation.width, y: start.y + value.translation.height)
            }
            .onEnded { _ in
                panStartOffset = nil
            }
    }

    /// Pinch-to-zoom, clamped to the same range as the macOS scroll-wheel/trackpad zoom handler.
    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if magnifyStartScale == nil { magnifyStartScale = scale }
                guard let start = magnifyStartScale else { return }
                scale = min(max(start * value, 0.2), 2.0)
            }
            .onEnded { _ in
                magnifyStartScale = nil
            }
    }

    #endif

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
