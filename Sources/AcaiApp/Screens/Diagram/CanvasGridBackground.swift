import SwiftUI

struct CanvasGridBackground: View {
    let scale: CGFloat
    let offset: CGPoint

    private let dotSpacing: CGFloat = 24
    private let dotRadius: CGFloat = 1.5
    private let dotColor = Color.gray.opacity(0.25)

    var body: some View {
        Canvas { context, size in
            let effectiveSpacing = dotSpacing * scale

            // Skip when too zoomed out for dots to stay legible.
            guard effectiveSpacing > 6 else { return }

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
