import SwiftUI
import AcaiDiagram
import AcaiGit
import AcaiRender

/// A small floating control, overlaid on a diagram's canvas, that opens `CompareGitPanel` in a
/// popover (macOS) or sheet (iOS/iPadOS). Deliberately not a permanent on-canvas bar: comparing
/// against git is an occasional action, not something that should cost canvas space (or, on a
/// narrow window, wrap into unreadable multi-line text) on every diagram view all the time.
///
/// iOS/iPadOS use `.sheet` rather than `.popover` + `.presentationCompactAdaptation(.sheet)`:
/// confirmed empirically (both in a live run and in this button's own XCUITest journeys) that a
/// `.popover` anchored to a small overlay button on top of a `GeometryReader`-driven canvas
/// presented literally no visible content on iOS — just the button itself, nothing over it — even
/// with compact adaptation set correctly on the presented content. `.sheet` doesn't share that
/// anchor-dependent presentation and is reliable here; macOS's popover (anchored via AppKit, not
/// this button's on-canvas frame) doesn't have the same failure mode.
struct CompareOverlayButton: View {
    let diagram: GeneratedDiagram
    @EnvironmentObject private var model: ProjectBrowserViewModel
    @State private var isPresented = false

    private var isOn: Bool { diagram.comparisonGitRef != nil }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            // "arrow.triangle.branch.circle[.fill]" isn't an SF Symbol Apple actually ships (no
            // circled variant exists for this compound glyph) — `Image(systemName:)` silently
            // renders nothing for an unknown name, which is exactly the "button with no visible
            // icon" bug reported against this control. Use the base glyph (confirmed valid — it's
            // the same one `CompareGitPanel`'s own `Label` already uses) and signal the on/off
            // state via the background fill instead of a nonexistent icon variant, so the state
            // isn't color-alone either: a filled colored circle vs. a plain translucent one.
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
            NavigationStack {
                CompareGitPanel(diagram: diagram)
                    .navigationTitle("Compare vs git")
                    .toolbar { clearToolbarItem }
            }
        }
        #else
        .sheet(isPresented: $isPresented) {
            // A sheet, unlike a popover, has no tap-outside-to-dismiss affordance and no built-in
            // close chrome of its own — an explicit Done button is the discoverable, VoiceOver-
            // reachable dismiss path (relying on swipe-to-dismiss alone would be as bad as the
            // inspector's iPhone close-button gap this pass already fixed elsewhere).
            NavigationStack {
                CompareGitPanel(diagram: diagram)
                    .navigationTitle("Compare vs git")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        clearToolbarItem
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

    /// A real nav-bar button, not a row inside the panel's own content — "Clear" is the counterpart
    /// to picking a ref from the list, not one more list item, so it lives in the same chrome
    /// "Done" does rather than at the top of the scrollable content underneath.
    private var clearToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Clear") {
                model.updateComparisonGitRef(diagramID: diagram.id, ref: nil)
            }
            .disabled(diagram.comparisonGitRef == nil)
            .accessibilityIdentifier("delta.clearButton")
        }
    }
}

/// The actual comparison controls (previously a permanent on-canvas bar): comparing the codebase's
/// current working tree against a git revision (`HEAD`, a branch, a SHA, …) and colour-coding the
/// added/removed/changed elements. Reads and writes the diagram's `comparisonGitRef` through the
/// model; the actual snapshot load is driven by the host view's `.task`. Presented inside
/// `CompareOverlayButton`'s popover/sheet.
struct CompareGitPanel: View {
    /// One row in the inline ref list below — deliberately a single, always-visible list rather
    /// than a toggle plus a separate text field plus a separate "pick a branch" menu: picking a ref
    /// enables the diff directly against it, with no on/off step and no extra tap to reveal the
    /// choices first. There's no "None" row — comparison starts with nothing selected, and the
    /// leading `Clear` button (not a list row) is what turns it back off.
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

        /// The accessibility-identifier suffix — deliberately the plain ref name (`"main"`, not
        /// `id`'s kind-prefixed `"branch-main"`), so a UI test can target a known fixture ref name
        /// directly without needing to know or guess its kind.
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
        // A literal branch/tag named "HEAD" would otherwise show up as a second, confusingly
        // identical-looking row alongside the dedicated `.head` entry above — the dedicated row
        // already covers that name unambiguously, so exclude it here rather than showing both.
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
            // The nav-bar Clear button lives on `CompareOverlayButton`, a different view instance
            // from this panel, so it can't reach into `isEditingCustomRef` directly — sync this
            // panel's own "Custom…" field visibility to the model whenever comparison turns off,
            // rather than only ever setting it from this view's own `select(_:)`.
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
