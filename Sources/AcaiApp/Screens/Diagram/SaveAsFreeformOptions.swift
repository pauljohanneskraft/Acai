import SwiftUI

/// The "Save as Freeform" confirmation shared by the two diagram types that have an opt-in metric
/// to carry over (Package Diagram, Call Graph): a single checkbox, "Include current
/// coupling/coverage figures as read-only notes," gating whether the conversion appends a `.note`
/// summarizing the coupling/coverage figures already computed for the live diagram, instead of
/// silently dropping them.
///
/// macOS presents this as a `.popover` (dismissible by clicking away, so only "Save" is needed).
/// iOS/iPadOS use `.sheet` + `NavigationStack` with explicit Cancel/Save controls instead: a bare
/// `.popover` collapses to a chrome-less full-screen sheet on compact width, with no reachable
/// dismiss control for a form this simple. `CompareOverlayButton` (`CompareGitOverlay.swift`) hits
/// the identical platform split for the identical reason — mirrored here rather than reinvented.
struct SaveAsFreeformOptionsModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var includeMetricsNote: Bool
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        #if os(macOS)
        content.popover(isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: 16) {
                Text(.app("View.SaveAsFreeformOptionsModifier.SaveFreeform")).font(.headline)
                metricsToggle
                HStack {
                    Spacer()
                    Button(.app("View.SaveAsFreeformOptionsModifier.Cancel")) { isPresented = false }
                        .accessibilityIdentifier("diagram.saveAsFreeform.cancelButton")
                    Button(.app("View.SaveAsFreeformOptionsModifier.Save")) {
                        isPresented = false
                        onConfirm()
                    }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("diagram.saveAsFreeform.confirmButton")
                }
            }
            .padding()
            .frame(width: 340)
        }
        #else
        content.sheet(isPresented: $isPresented) {
            NavigationStack {
                Form {
                    metricsToggle
                }
                .navigationTitle(.app("View.SaveAsFreeformOptionsModifier.SaveFreeform"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(.app("View.SaveAsFreeformOptionsModifier.Cancel")) { isPresented = false }
                            .accessibilityIdentifier("diagram.saveAsFreeform.cancelButton")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(.app("View.SaveAsFreeformOptionsModifier.Save")) {
                            isPresented = false
                            onConfirm()
                        }
                        .accessibilityIdentifier("diagram.saveAsFreeform.confirmButton")
                    }
                }
            }
            .presentationDetents([.medium])
        }
        #endif
    }

    private var metricsToggle: some View {
        Toggle(.app("View.SaveAsFreeformOptionsModifier.IncludeCurrentCouplingCoverage"), isOn: $includeMetricsNote)
            .accessibilityIdentifier("diagram.saveAsFreeform.includeMetricsToggle")
    }
}

extension View {
    func saveAsFreeformOptions(
        isPresented: Binding<Bool>,
        includeMetricsNote: Binding<Bool>,
        onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(SaveAsFreeformOptionsModifier(
            isPresented: isPresented, includeMetricsNote: includeMetricsNote, onConfirm: onConfirm
        ))
    }
}
