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

    /// Changes when a diagram's comparison revision or its loaded snapshots do, for the diagram to
    /// re-derive itself in place. Resetting its identity instead would close the compare panel
    /// presented over it: on macOS that panel is an `NSPopover`, which AppKit dismisses when the
    /// hierarchy it was opened over is torn down, from whichever ancestor it is anchored.
    var comparisonIdentity: String {
        get { self[ComparisonIdentityKey.self] }
        set { self[ComparisonIdentityKey.self] = newValue }
    }
}

private struct DiagramHasBeenFittedKey: EnvironmentKey {
    static let defaultValue: Binding<Bool>? = nil
}

private struct ComparisonIdentityKey: EnvironmentKey {
    static let defaultValue = ""
}

/// Owns the delta-comparison "is the panel open" state for one diagram and hands it down as a
/// `Binding`, so `CompareOverlayButton` can sit inside the diagram's own canvas without losing that
/// state when the ref changes. A comparison change reaches the diagram as `comparisonIdentity`, for
/// it to re-derive itself in place, rather than as a new identity for `content` — which would tear
/// down the panel presented over it. The panel is never presented from inside `content` either: the
/// sheet is presented here, the popover by `ComparePopoverPresenter`.
struct DeltaHostedDiagramView<Content: View>: View {
    let diagram: GeneratedDiagram
    @ViewBuilder var content: (Binding<Bool>) -> Content
    @EnvironmentObject private var model: ProjectBrowserViewModel
    @State private var hasBeenFitted = false
    #if os(macOS)
    @Environment(\.comparePopover) private var comparePopover
    #else
    @State private var isSheetPresented = false
    @State private var sheetChangedFileSelection: Set<String>?
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

    private var contentIdentity: String {
        "\(comparisonTaskID)|\(loaded)"
    }

    #if os(macOS)
    private var isComparePresented: Binding<Bool> {
        guard let comparePopover else { return .constant(false) }
        let diagramID = diagram.id
        return Binding(
            get: { comparePopover.isPresented(for: diagramID) },
            set: { comparePopover.setPresented($0, for: diagramID) })
    }

    private var changedFileSelection: Binding<Set<String>?> {
        guard let comparePopover else { return .constant(nil) }
        return Binding(
            get: { comparePopover.changedFileSelection },
            set: { comparePopover.changedFileSelection = $0 })
    }
    #else
    private var isComparePresented: Binding<Bool> { $isSheetPresented }
    private var changedFileSelection: Binding<Set<String>?> { $sheetChangedFileSelection }

    /// `nil` hides the panel's per-file select button where the diagram has nothing to select.
    private var selectChangedFileTypes: ((Set<String>) -> Void)? {
        guard diagram.type.selectsChangedFileTypes else { return nil }
        return { sheetChangedFileSelection = $0 }
    }
    #endif

    var body: some View {
        // `.task(id:)` sits on this `ZStack` so it's governed only by `comparisonTaskID`:
        // `contentIdentity` additionally includes `loaded`, and a task keyed on that would restart
        // every time `loaded` flips, redundantly re-invoking `ensureComparisonLoaded` right as
        // loading finishes. A single-child `ZStack` is layout-neutral — nothing to size/align
        // against — so this changes only the task's lifecycle.
        ZStack {
            content(isComparePresented)
                .environment(\.comparisonIdentity, contentIdentity)
                .environment(\.compareChangedFileSelection, changedFileSelection)
                .environment(\.diagramHasBeenFitted, $hasBeenFitted)
        }
        .task(id: comparisonTaskID) {
            await model.ensureComparisonLoaded(for: diagram)
        }
        #if os(macOS)
        .onDisappear {
            guard let comparePopover, comparePopover.isPresented(for: diagram.id) else { return }
            comparePopover.close()
            comparePopover.changedFileSelection = nil
        }
        #else
        // Not a `.popover` + `.presentationCompactAdaptation(.sheet)`: a popover anchored to a small
        // overlay button on a `GeometryReader`-driven canvas renders no visible content on iOS.
        .sheet(isPresented: $isSheetPresented) {
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
                            Button(.app("View.CompareOverlayButton.Done")) { isSheetPresented = false }
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
}
