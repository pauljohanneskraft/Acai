import SwiftUI
import AcaiCore

private struct CompareChangedFileSelectionKey: EnvironmentKey {
    static let defaultValue: Binding<Set<String>?> = .constant(nil)
}

extension EnvironmentValues {
    /// Type ids of a changed file picked in the iOS compare sheet, for the diagram to select; the
    /// diagram clears it once applied. The sheet lives outside the diagram's identity boundary, so
    /// the pick can't be a closure the diagram hands to the panel.
    var compareChangedFileSelection: Binding<Set<String>?> {
        get { self[CompareChangedFileSelectionKey.self] }
        set { self[CompareChangedFileSelectionKey.self] = newValue }
    }
}

/// Owns the delta-comparison "is the panel open" state for one diagram, one level above that
/// diagram's own `.id(...)` boundary, and hands it down as a `Binding` so `CompareOverlayButton`
/// can be placed inside the diagram's own canvas without losing that state when the ref changes.
///
/// Picking a ref resets `content`'s identity twice in quick succession (the ref, then `loaded`).
/// On iOS the sheet is therefore presented from here, outside that boundary: presented from inside
/// it, each reset tore the presenter down mid-presentation, and re-presenting raced the old sheet's
/// dismissal — the panel intermittently vanished while the user was using it.
///
/// On macOS the popover must stay anchored to the button inside `content`, so a reset still tears
/// it down; a real `false` → `true` transition after the resets settle re-presents it on the new
/// instance, coalesced so back-to-back resets schedule one re-present.
struct DeltaHostedDiagramView<Content: View>: View {
    let diagram: GeneratedDiagram
    @ViewBuilder var content: (Binding<Bool>) -> Content
    @EnvironmentObject private var model: ProjectBrowserViewModel
    @State private var isComparePresented = false
    @State private var changedFileSelection: Set<String>?
    #if os(macOS)
    @State private var reopensCompare = false
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
                #if os(macOS)
                .onChange(of: contentIdentity) { _, _ in
                    guard isComparePresented || reopensCompare else { return }
                    isComparePresented = false
                    reopensCompare = true
                    DispatchQueue.main.async {
                        guard reopensCompare else { return }
                        reopensCompare = false
                        isComparePresented = true
                    }
                }
                #endif
        }
        .task(id: comparisonTaskID) {
            await model.ensureComparisonLoaded(for: diagram)
        }
        #if !os(macOS)
        .sheet(isPresented: $isComparePresented) {
            // A sheet has no built-in close chrome, so an explicit Done button is the discoverable
            // dismiss path (unlike macOS's popover, a sheet's `NavigationStack` toolbar renders
            // correctly here).
            NavigationStack {
                CompareGitPanel(diagram: diagram, onSelectChangedFileTypes: { changedFileSelection = $0 })
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
            .presentationDetents([.medium])
            .environmentObject(model)
        }
        #endif
    }
}
