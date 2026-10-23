import SwiftUI
import AcaiCore

private struct CompareChangedFileSelectionKey: EnvironmentKey {
    static let defaultValue: Binding<Set<String>?> = .constant(nil)
}

extension EnvironmentValues {
    /// Type ids of a changed file picked in the compare panel, for the diagram to select; the
    /// diagram clears it once applied. The panel lives outside the diagram's identity boundary, so
    /// the pick can't be a closure the diagram hands to the panel.
    var compareChangedFileSelection: Binding<Set<String>?> {
        get { self[CompareChangedFileSelectionKey.self] }
        set { self[CompareChangedFileSelectionKey.self] = newValue }
    }

    /// Whether the diagram has been fitted to its canvas since it was opened, owned above its identity
    /// boundary: a rebuild when a comparison loads keeps the user's zoom and pan instead of re-fitting
    /// against a canvas that may still be mid-layout. `nil` outside a `DeltaHostedDiagramView`.
    var diagramHasBeenFitted: Binding<Bool>? {
        get { self[DiagramHasBeenFittedKey.self] }
        set { self[DiagramHasBeenFittedKey.self] = newValue }
    }

    /// Reports the compare button's window frame to its host, which anchors the macOS popover there.
    /// Report-only: the button never reads the anchor back, which is kept in the host's coordinates.
    var reportCompareButtonFrame: ((CGRect) -> Void)? {
        get { self[CompareButtonFrameKey.self] }
        set { self[CompareButtonFrameKey.self] = newValue }
    }
}

private struct DiagramHasBeenFittedKey: EnvironmentKey {
    static let defaultValue: Binding<Bool>? = nil
}

private struct CompareButtonFrameKey: EnvironmentKey {
    static let defaultValue: ((CGRect) -> Void)? = nil
}

/// Owns the delta-comparison "is the panel open" state for one diagram, one level above that
/// diagram's own `.id(...)` boundary, and hands it down as a `Binding` so `CompareOverlayButton`
/// can be placed inside the diagram's own canvas without losing that state when the ref changes.
///
/// Picking a ref resets `content`'s identity twice in quick succession (the ref, then `loaded`), so
/// both presentations are made from here, outside that boundary, where a reset never touches them:
/// presented from inside it, each reset tore the presenter down mid-presentation and re-presenting
/// raced the old presentation's dismissal — the panel vanished while the user was using it.
struct DeltaHostedDiagramView<Content: View>: View {
    let diagram: GeneratedDiagram
    @ViewBuilder var content: (Binding<Bool>) -> Content
    @EnvironmentObject private var model: ProjectBrowserViewModel
    @State private var isComparePresented = false
    @State private var changedFileSelection: Set<String>?
    @State private var hasBeenFitted = false
    #if os(macOS)
    @State private var compareAnchor = CompareAnchor()
    #else
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    /// A pull-request comparison needs both the "old" (merge-base) and "new" (head) snapshots
    /// before the union diagram can render; the two pre-existing modes only ever load the "old"
    /// side (the "new" side is the live working tree, already available).
    private var loaded: Bool {
        model.comparisonArtifact(for: diagram) != nil
            && (diagram.comparisonBaseRef == nil || model.comparisonNewArtifact(for: diagram) != nil)
    }

    private var comparisonTaskID: String {
        "\(diagram.id)|\(diagram.comparisonGitRef ?? "")|\(diagram.comparisonBaseRef ?? "")"
    }

    /// `nil` hides the panel's per-file select button where the diagram has nothing to select.
    private var selectChangedFileTypes: ((Set<String>) -> Void)? {
        guard diagram.type.selectsChangedFileTypes else { return nil }
        return { changedFileSelection = $0 }
    }

    private var contentIdentity: String {
        "\(comparisonTaskID)|\(loaded)"
    }

    var body: some View {
        // `.task(id:)` sits on this `ZStack`, not on `content`, so it's governed only by
        // `comparisonTaskID` — `content`'s own `.id()` below additionally includes `loaded`, and a
        // `.task` chained onto that identity would restart every time `loaded` flips, redundantly
        // re-invoking `ensureComparisonLoaded` right as loading finishes. A single-child `ZStack` is
        // layout-neutral — nothing to size/align against — so this changes only the task's lifecycle.
        ZStack {
            content($isComparePresented)
                .id(contentIdentity)
                .environment(\.compareChangedFileSelection, $changedFileSelection)
                .environment(\.diagramHasBeenFitted, $hasBeenFitted)
                #if os(macOS)
                .environment(\.reportCompareButtonFrame) { frame in
                    compareAnchor.update(button: frame, isPanelPresented: isComparePresented)
                }
                #endif
        }
        .task(id: comparisonTaskID) {
            await model.ensureComparisonLoaded(for: diagram)
        }
        #if os(macOS)
        // On a leaf placed over the button, not on this `ZStack`: every diagram's content carries an
        // `.inspector`, which on macOS hoists it into a split view, and a popover attached to a view
        // wrapping that content never presents. The leaf's placement comes from `CompareAnchor`
        // rather than from a live `GeometryReader`, so nothing moves it while the popover is up.
        .overlay {
            if let placement = compareAnchor.placement {
                Color.clear
                    .frame(width: placement.width, height: placement.height)
                    .popover(isPresented: $isComparePresented) { comparePopover }
                    .position(x: placement.midX, y: placement.midY)
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            compareAnchor.update(host: frame, isPanelPresented: isComparePresented)
        }
        #else
        // Not a `.popover` + `.presentationCompactAdaptation(.sheet)`: a popover anchored to a small
        // overlay button on a `GeometryReader`-driven canvas renders no visible content on iOS.
        .sheet(isPresented: $isComparePresented) {
            // A sheet has no built-in close chrome, so an explicit Done button is the discoverable
            // dismiss path (unlike macOS's popover, a sheet's `NavigationStack` toolbar renders
            // correctly here).
            NavigationStack {
                CompareGitPanel(diagram: diagram, onSelectChangedFileTypes: selectChangedFileTypes)
                    .navigationTitle(.app("View.CompareOverlayButton.CompareVsGit"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { CompareClearButton(diagram: diagram) }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(.app("View.CompareOverlayButton.Done")) { isComparePresented = false }
                                .accessibilityIdentifier("delta.doneButton")
                        }
                    }
            }
            // A medium form sheet is too short for a loaded comparison, which then overflows and slides
            // the ref list under the Clear button.
            .presentationDetents(horizontalSizeClass == .regular ? [.large] : [.medium])
            .environmentObject(model)
        }
        #endif
    }

    #if os(macOS)
    /// Not `NavigationStack { ... .toolbar { clearButton } }`: on macOS, a `.toolbar` inside a
    /// `NavigationStack` presented in a `.popover` renders its items in the presenting window's own
    /// toolbar instead of inside the popover.
    private var comparePopover: some View {
        VStack(alignment: .leading, spacing: .zero) {
            HStack {
                Text(.app("View.CompareOverlayButton.CompareVsGit")).font(.headline)
                Spacer()
                CompareClearButton(diagram: diagram)
            }
            .padding()
            Divider()
            CompareGitPanel(diagram: diagram, onSelectChangedFileTypes: selectChangedFileTypes)
        }
        .environmentObject(model)
    }
    #endif
}
