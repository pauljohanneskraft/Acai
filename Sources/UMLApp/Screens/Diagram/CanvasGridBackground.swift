import SwiftUI

/// A subtle dot-grid background that provides visual feedback for the infinite canvas.
struct CanvasGridBackground: View {
    let scale: CGFloat
    let offset: CGPoint

    private let dotSpacing: CGFloat = 24
    private let dotRadius: CGFloat = 1.0
    private let dotColor = Color.gray.opacity(0.25)

    var body: some View {
        Canvas { context, size in
            let effectiveSpacing = dotSpacing * scale

            // Don't draw grid if too zoomed out (dots would be too dense)
            // or too zoomed in (dots would be too sparse).
            guard effectiveSpacing > 6 else { return }

            // Compute the offset of the first dot in screen space.
            let startX = offset.x.truncatingRemainder(dividingBy: effectiveSpacing)
            let startY = offset.y.truncatingRemainder(dividingBy: effectiveSpacing)

            let radius = dotRadius * min(scale, 1.5)

            var x = startX
            while x < size.width {
                var y = startY
                while y < size.height {
                    let rect = CGRect(
                        x: x - radius,
                        y: y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(dotColor))
                    y += effectiveSpacing
                }
                x += effectiveSpacing
            }
        }
    }
}
