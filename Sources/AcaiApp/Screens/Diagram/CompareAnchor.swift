import CoreGraphics

/// Follows the compare button, so the popover moves with it when the inspector or the window resizes the canvas.
struct CompareAnchor: Equatable {
    private var buttonFrame = CGRect.zero
    private var hostFrame = CGRect.zero

    /// `nil` until both frames are known: a zero rect would open the popover in the window's corner.
    var placement: CGRect? {
        guard !buttonFrame.isEmpty, !hostFrame.isEmpty else { return nil }
        return buttonFrame.offsetBy(dx: -hostFrame.minX, dy: -hostFrame.minY)
    }

    mutating func update(button frame: CGRect) {
        guard !frame.isEmpty else { return }
        buttonFrame = frame
    }

    mutating func update(host frame: CGRect) {
        guard !frame.isEmpty else { return }
        hostFrame = frame
    }
}
