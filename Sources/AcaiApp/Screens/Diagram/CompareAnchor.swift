import CoreGraphics

/// Where the macOS compare popover attaches, in `DeltaHostedDiagramView`'s own coordinates: the
/// compare button's window frame against the host's, both taken only while the panel is closed.
///
/// Both report their geometry live, and both move when a comparison changes — the button is rebuilt
/// inside the diagram's identity boundary, and the host's measured frame follows that content being
/// torn down and laid out again. AppKit closes a popover whose positioning rect leaves the window,
/// so a report arriving while the popover is up is dropped, and an empty rect never taken at all.
struct CompareAnchor: Equatable {
    private var button = CGRect.zero
    private var host = CGRect.zero

    /// The button's frame relative to the host, or `nil` until both have reported a real one — a
    /// popover anchored at the origin with no size opens in the window's corner, not on the button.
    var placement: CGRect? {
        guard !button.isEmpty, !host.isEmpty else { return nil }
        return button.offsetBy(dx: -host.minX, dy: -host.minY)
    }

    mutating func update(button frame: CGRect, isPanelPresented: Bool) {
        guard !frame.isEmpty, !isPanelPresented else { return }
        button = frame
    }

    mutating func update(host frame: CGRect, isPanelPresented: Bool) {
        guard !frame.isEmpty, !isPanelPresented else { return }
        host = frame
    }
}
