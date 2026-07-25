import SwiftUI
import AcaiDiagram
import AcaiGit
import AcaiRender

/// A small floating control, overlaid on a diagram's canvas, that opens `CompareGitPanel` in a
/// popover (macOS) or sheet (iOS/iPadOS). Deliberately not a permanent on-canvas bar: comparing
/// against git is occasional and shouldn't cost canvas space on every diagram view.
///
/// iOS/iPadOS use `.sheet` rather than `.popover` + `.presentationCompactAdaptation(.sheet)`: a
/// `.popover` anchored to a small overlay button on a `GeometryReader`-driven canvas renders no
/// visible content on iOS. `.sheet` doesn't share that anchor-dependent presentation.
struct CompareOverlayButton: View {
    let diagram: GeneratedDiagram
    /// Owned by a stable ancestor above the diagram's own `.id(...)` boundary (`DeltaHostedDiagramView`),
    /// not this view itself: this button renders inside the diagram's canvas, so its view identity
    /// resets whenever the comparison ref changes. Storing the boolean outside that boundary lets the
    /// value survive the reset — see `DeltaHostedDiagramView`'s doc comment.
    @Binding var isPresented: Bool
    @EnvironmentObject private var model: ProjectBrowserViewModel

    private var isOn: Bool { diagram.comparisonGitRef != nil }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            // No circled variant of this glyph exists in SF Symbols — `Image(systemName:)` would
            // silently render nothing. Use the base glyph and signal on/off via the background fill
            // (filled colored circle vs. plain translucent one) instead, so state isn't color-alone.
            Image(systemName: "arrow.triangle.branch")
                .font(.title3)
                .foregroundStyle(isOn ? .white : Color.secondary)
        }
        .buttonStyle(.plain)
        .padding(8)
        .background(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.thinMaterial), in: Circle())
        .padding(10)
        .help(isOn ? "Comparing vs \(diagram.comparisonGitRef ?? "")" : "Compare vs git")
        .accessibilityLabel(isOn ? "Compare vs git, comparison active" : "Compare vs git")
        .accessibilityIdentifier("delta.openButton")
        #if os(macOS)
        .popover(isPresented: $isPresented) {
            // Not `NavigationStack { ... .toolbar { clearButton } }`: on macOS, a `.toolbar` inside a
            // `NavigationStack` presented in a `.popover` renders its items in the presenting window's
            // own toolbar instead of inside the popover. A plain header row sidesteps that.
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Compare vs git").font(.headline)
                    Spacer()
                    clearButton
                }
                .padding()
                Divider()
                CompareGitPanel(diagram: diagram)
            }
        }
        #else
        .sheet(isPresented: $isPresented) {
            // A sheet has no built-in close chrome, so an explicit Done button is the discoverable,
            // VoiceOver-reachable dismiss path. Unlike macOS's popover, a sheet's `NavigationStack`
            // toolbar renders correctly inside it.
            NavigationStack {
                CompareGitPanel(diagram: diagram)
                    .navigationTitle("Compare vs git")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { clearButton }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isPresented = false }
                                .accessibilityIdentifier("delta.doneButton")
                        }
                    }
            }
            .presentationDetents([.medium])
        }
        #endif
    }

    /// "Clear" is the counterpart to picking a ref from the list, not one more list item, so it
    /// lives in the panel's header chrome rather than at the top of the scrollable content
    /// underneath — a real button shared verbatim between macOS's inline header row and iOS's
    /// nav-bar toolbar item.
    private var clearButton: some View {
        Button("Clear") {
            model.updateComparisonGitRef(diagramID: diagram.id, ref: nil)
        }
        .disabled(diagram.comparisonGitRef == nil)
        .accessibilityIdentifier("delta.clearButton")
    }
}

/// Owns the delta-comparison "is the panel open" state for one diagram, one level above that
/// diagram's own `.id(...)` boundary, and hands it down as a `Binding` so `CompareOverlayButton`
/// can be placed inside the diagram's own canvas without losing that state when the ref changes.
///
/// `content`'s `.id(...)` must stay scoped to the diagram view, not this wrapper: if
/// `CompareOverlayButton` owned `isPresented` itself, changing the ref would tear the button down
/// (new id) and silently reset it, dismissing the panel. Storing the boolean here, outside the
/// identity boundary, lets it survive.
///
/// That alone isn't enough: `.popover`/`.sheet(isPresented:)` react to the binding *changing*, not
/// to a freshly mounted view observing an already-`true` value, and a ref change recreates the
/// button already "on." Forcing a real `false` → `true` transition right after the id changes is
/// what re-triggers presentation on the new instance.
struct DeltaHostedDiagramView<Content: View>: View {
    let diagram: GeneratedDiagram
    @ViewBuilder var content: (Binding<Bool>) -> Content
    @EnvironmentObject private var model: ProjectBrowserViewModel
    @State private var isComparePresented = false

    var body: some View {
        let loaded = model.comparisonArtifact(for: diagram) != nil
        content($isComparePresented)
            .id("\(diagram.id)|\(diagram.comparisonGitRef ?? "")|\(loaded)")
            .task(id: "\(diagram.id)|\(diagram.comparisonGitRef ?? "")") {
                await model.ensureComparisonLoaded(for: diagram)
            }
            .onChange(of: diagram.comparisonGitRef) { _, _ in
                guard isComparePresented else { return }
                isComparePresented = false
                DispatchQueue.main.async { isComparePresented = true }
            }
    }
}

/// The actual comparison controls (previously a permanent on-canvas bar): comparing the codebase's
/// current working tree against a git revision (`HEAD`, a branch, a SHA, …) and colour-coding the
/// added/removed/changed elements. Reads and writes the diagram's `comparisonGitRef` through the
/// model; the actual snapshot load is driven by the host view's `.task`. Presented inside
/// `CompareOverlayButton`'s popover/sheet.
struct CompareGitPanel: View {
    /// One row in the inline ref list: picking a ref enables the diff directly, no on/off step.
    /// There's no "None" row — the leading `Clear` button turns comparison back off.
    private enum RefRow: Hashable, Identifiable {
        case head
        case ref(GitCheckout.Ref)
        case custom

        var id: String {
            switch self {
            case .head:
                "HEAD"
            case .ref(let ref):
                ref.id
            case .custom:
                "custom"
            }
        }

        var name: String {
            switch self {
            case .head:
                "HEAD"
            case .ref(let ref):
                ref.name
            case .custom:
                "Custom…"
            }
        }

        /// The trailing kind badge — `nil` for Custom, which isn't a ref at all.
        var kindLabel: String? {
            switch self {
            case .custom:
                nil
            case .head:
                "HEAD"
            case .ref(let ref):
                ref.kind == .branch ? "Branch" : "Tag"
            }
        }

        /// The accessibility-identifier suffix — the plain ref name (not `id`'s kind-prefixed form),
        /// so a UI test can target a known fixture ref name without guessing its kind.
        var testIdentifier: String {
            switch self {
            case .head:
                "HEAD"
            case .ref(let ref):
                ref.name
            case .custom:
                "custom"
            }
        }
    }

    let diagram: GeneratedDiagram
    @EnvironmentObject private var model: ProjectBrowserViewModel
    @State private var availableRefs: [GitCheckout.Ref] = []
    @State private var isEditingCustomRef = false
    @State private var customRefText = ""

    private var rows: [RefRow] {
        // Exclude a literal branch/tag named "HEAD" — the dedicated `.head` row above already covers it.
        [.head] + availableRefs.filter { $0.name != "HEAD" }.map(RefRow.ref) + [.custom]
    }

    /// `nil` when comparison is off — no row shows a checkmark in that state.
    private var selectedRow: RefRow? {
        guard let ref = diagram.comparisonGitRef else { return nil }
        if ref == "HEAD" { return .head }
        if let match = availableRefs.first(where: { $0.name == ref }) { return .ref(match) }
        return .custom
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(rows) { row in
                Button {
                    select(row)
                } label: {
                    HStack {
                        Text(row.name)
                        Spacer()
                        if let kindLabel = row.kindLabel {
                            Text(kindLabel)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if row == selectedRow {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("delta.ref.\(row.testIdentifier)")
            }
            .listStyle(.plain)
            .task { loadAvailableRefs() }
            .frame(minHeight: 150, maxHeight: 260)
            // The nav-bar Clear button lives on a different view instance and can't reach
            // `isEditingCustomRef` directly, so sync it from the model when comparison turns off.
            .onChange(of: diagram.comparisonGitRef) { _, newValue in
                if newValue == nil { isEditingCustomRef = false }
            }

            VStack(alignment: .leading, spacing: 12) {
                if isEditingCustomRef {
                    TextField("ref (a SHA, HEAD~3, …)", text: $customRefText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { model.updateComparisonGitRef(diagramID: diagram.id, ref: customRefText) }
                        .accessibilityIdentifier("delta.customRefField")
                }

                if diagram.comparisonGitRef != nil {
                    legend
                    statusLine
                }
            }
            .padding(16)
        }
        .frame(minWidth: 260, alignment: .leading)
    }

    private func select(_ row: RefRow) {
        switch row {
        case .head:
            isEditingCustomRef = false
            model.updateComparisonGitRef(diagramID: diagram.id, ref: "HEAD")
        case .ref(let ref):
            isEditingCustomRef = false
            model.updateComparisonGitRef(diagramID: diagram.id, ref: ref.name)
        case .custom:
            customRefText = diagram.comparisonGitRef ?? "HEAD"
            isEditingCustomRef = true
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if let error = model.comparisonError {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
                .accessibilityIdentifier("delta.error")
        } else if model.comparisonArtifact(for: diagram) == nil {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Loading \(diagram.comparisonGitRef ?? "")…").font(.caption).foregroundStyle(.secondary)
            }
        } else {
            Text("Loaded").font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("delta.loaded")
        }
    }

    /// Loads the codebase's branch/tag refs for the list. Best-effort: a failure (e.g. not a git
    /// repository) just leaves the list showing only HEAD/Custom.
    private func loadAvailableRefs() {
        guard let codebase = model.codebase(for: diagram.codebaseID) else { return }
        let directory = URL(fileURLWithPath: codebase.directoryPath)
        availableRefs = (try? GitCheckout(directory: directory).refs()) ?? []
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
