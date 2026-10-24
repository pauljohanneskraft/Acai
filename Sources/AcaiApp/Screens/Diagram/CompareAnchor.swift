import CoreGraphics

/// The compare button's frame relative to the view presenting the macOS popover, held still while the
/// popover is up because AppKit closes a popover whose positioning rect leaves the window.
struct CompareAnchor: Equatable {
    private var buttonFrame = CGRect.zero
    private var hostFrame = CGRect.zero
    private var isHeld = false
    private var heldPlacement: CGRect?

    /// `nil` until both frames are known: a zero rect would open the popover in the window's corner.
    var placement: CGRect? {
        heldPlacement ?? livePlacement
    }

    private var livePlacement: CGRect? {
        guard !buttonFrame.isEmpty, !hostFrame.isEmpty else { return nil }
        return buttonFrame.offsetBy(dx: -hostFrame.minX, dy: -hostFrame.minY)
    }

    mutating func update(button frame: CGRect) {
        guard !frame.isEmpty else { return }
        buttonFrame = frame
        holdFirstKnownPlacement()
    }

    mutating func update(host frame: CGRect) {
        guard !frame.isEmpty else { return }
        hostFrame = frame
        holdFirstKnownPlacement()
    }

    mutating func holdStill(_ isHeld: Bool) {
        guard isHeld != self.isHeld else { return }
        self.isHeld = isHeld
        heldPlacement = nil
        holdFirstKnownPlacement()
    }

    private mutating func holdFirstKnownPlacement() {
        guard isHeld, heldPlacement == nil else { return }
        heldPlacement = livePlacement
    }
}
