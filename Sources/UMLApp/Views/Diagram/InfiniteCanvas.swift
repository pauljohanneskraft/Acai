import SwiftUI

/// A reusable infinite canvas container that supports pan, zoom, and scroll-wheel zoom.
/// Content is rendered in a transformed coordinate space.
struct InfiniteCanvas<Content: View>: View {
    @Binding var scale: CGFloat
    @Binding var offset: CGPoint

    @State private var dragStart: CGPoint? = nil

    let content: () -> Content

    init(
        scale: Binding<CGFloat>,
        offset: Binding<CGPoint>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._scale = scale
        self._offset = offset
        self.content = content
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Grid background layer.
                CanvasGridBackground(scale: scale, offset: offset)

                // Transformed content layer.
                content()
                    .scaleEffect(scale, anchor: .topLeading)
                    .offset(x: offset.x, y: offset.y)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .contentShape(Rectangle())
            .background(Color(white: 0.96))
            .gesture(panGesture)
            #if os(macOS)
            .overlay(ScrollWheelZoomHandler(scale: $scale, offset: $offset))
            #endif
        }
    }

    // MARK: - Gestures

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = offset
                }
                guard let start = dragStart else { return }
                offset = CGPoint(
                    x: start.x + value.translation.width,
                    y: start.y + value.translation.height
                )
            }
            .onEnded { _ in
                dragStart = nil
            }
    }

}
