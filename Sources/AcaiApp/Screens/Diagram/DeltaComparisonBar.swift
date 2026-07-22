import SwiftUI
import AcaiDiagram
import AcaiGit
import AcaiRender

/// A control strip shown above a diagram that toggles **delta mode**: comparing the codebase's
/// current working tree against a git revision (`HEAD`, a branch, a SHA, …) and colour-coding the
/// added/removed/changed elements. Reads and writes the diagram's `comparisonGitRef` through the
/// model; the actual snapshot load is driven by the host view's `.task`.
struct DeltaComparisonBar: View {
    let diagram: GeneratedDiagram
    @EnvironmentObject private var model: ProjectBrowserViewModel
    @State private var refText: String
    @State private var availableRefs: [String] = []

    init(diagram: GeneratedDiagram) {
        self.diagram = diagram
        _refText = State(initialValue: diagram.comparisonGitRef ?? "HEAD")
    }

    private var isOn: Bool { diagram.comparisonGitRef != nil }

    var body: some View {
        HStack(spacing: 10) {
            Toggle(isOn: Binding(
                get: { isOn },
                set: { model.updateComparisonGitRef(diagramID: diagram.id, ref: $0 ? refText : nil) }
            )) {
                Label("Compare vs git", systemImage: "arrow.triangle.branch")
            }
            .toggleStyle(.switch)
            .accessibilityIdentifier("delta.toggle")

            if isOn {
                TextField("ref", text: $refText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
                    .onSubmit { model.updateComparisonGitRef(diagramID: diagram.id, ref: refText) }
                    .accessibilityIdentifier("delta.refField")

                refPicker
                    .task { loadAvailableRefs() }

                legend

                if let error = model.comparisonError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                        .accessibilityIdentifier("delta.error")
                } else if model.comparisonArtifact(for: diagram) == nil {
                    ProgressView().controlSize(.small)
                    Text("Loading \(refText)…").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Loaded").font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("delta.loaded")
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    /// A compact "pick a branch/tag" button next to the freeform ref field — `refText` still
    /// accepts any typed ref (a SHA, `HEAD~3`, …), this just saves typing an exact branch/tag name.
    private var refPicker: some View {
        Menu {
            if availableRefs.isEmpty {
                Text("No branches or tags found").font(.caption)
            } else {
                ForEach(availableRefs, id: \.self) { ref in
                    Button(ref) {
                        refText = ref
                        model.updateComparisonGitRef(diagramID: diagram.id, ref: ref)
                    }
                }
            }
        } label: {
            Image(systemName: "chevron.down.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Pick a branch or tag")
    }

    /// Loads the codebase's branch/tag names for `refPicker`. Best-effort: a failure (e.g. not a
    /// git repository) just leaves the picker showing "No branches or tags found".
    private func loadAvailableRefs() {
        guard let codebase = model.codebase(for: diagram.codebaseID) else { return }
        let directory = URL(fileURLWithPath: codebase.directoryPath)
        availableRefs = (try? GitCheckout(directory: directory).refNames()) ?? []
    }

    private var legend: some View {
        HStack(spacing: 10) {
            swatch(Color(hex: DeltaEdgeColors.standard.added), "added")
            swatch(Color(hex: DeltaEdgeColors.standard.removed), "removed")
            swatch(Color(hex: DeltaEdgeColors.standard.changed), "changed")
        }
    }

    private func swatch(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
