import CoreGraphics

/// Where the macOS compare popover attaches: the compare button's window frame, kept above the
/// diagram's `.id(...)` boundary by `DeltaHostedDiagramView`.
///
/// The button itself renders inside that boundary, so every comparison change destroys it and the
/// rebuilt one reports its geometry again from scratch. A report that moves the popover's
/// positioning rect while the popover is up closes it in AppKit — the panel then vanished on every
/// pick — so a report is taken only while the panel is closed, and an empty rect never at all.
struct CompareAnchor: Equatable {
    private(set) var frame = CGRect.zero

    /// `false` until the button has reported a real frame; a popover anchored at the origin with no
    /// size would open in the window's corner instead of on the button.
    var isResolved: Bool { !frame.isEmpty }

    mutating func update(to frame: CGRect, isPanelPresented: Bool) {
        guard !frame.isEmpty, !isPanelPresented else { return }
        self.frame = frame
    }
}
