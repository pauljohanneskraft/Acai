import SwiftUI
import AcaiCore
import AcaiDiagram
import AcaiDiff
import AcaiGit
import AcaiRender

/// A small floating control, overlaid on a diagram's canvas, that opens `CompareGitPanel` in a
/// popover (macOS) or sheet (iOS/iPadOS). Deliberately not a permanent on-canvas bar: comparing
/// against git is occasional and shouldn't cost canvas space on every diagram view.
///
/// iOS/iPadOS use `.sheet` rather than `.popover` + `.presentationCompactAdaptation(.sheet)`: a
/// `.popover` anchored to a small overlay button on a `GeometryReader`-driven canvas renders no
/// visible content on iOS. `.sheet` doesn't share that anchor-dependent presentation, so it is
/// presented by `DeltaHostedDiagramView` instead of by this button — see its doc comment.
struct CompareOverlayButton: View {
    let diagram: GeneratedDiagram
    /// Owned by a stable ancestor above the diagram's own `.id(...)` boundary (`DeltaHostedDiagramView`),
    /// not this view itself: this button renders inside the diagram's canvas, so its view identity
    /// resets whenever the comparison ref changes.
    @Binding var isPresented: Bool
    /// Invoked when a changed-files row is tapped, with that file's type ids — lets the host diagram
    /// view select/reveal those nodes. `nil` for a diagram type with no such concept (only Class
    /// Diagram wires this up today). On iOS the sheet reports it through
    /// `EnvironmentValues.compareChangedFileSelection` instead.
    var onSelectChangedFileTypes: ((Set<String>) -> Void)?

    private var isOn: Bool { diagram.comparisonGitRef != nil }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            // No circled variant of this glyph exists in SF Symbols — signal on/off via the
            // background fill instead, so state isn't color-alone.
            Image(systemName: "arrow.triangle.branch")
                .font(.title3)
                .foregroundStyle(isOn ? .white : Color.secondary)
        }
        // Chrome, not content: every other canvas-viewport control (the toolbar's undo/redo/fit/
        // search/sidebar icons) stays a fixed size regardless of Dynamic Type, since a bar-button
        // icon growing with accessibility text sizes has nowhere bigger to go without overlapping
        // its neighbours. Pinned here so this floating button matches that convention instead of
        // silently ballooning while everything around it stays put.
        .dynamicTypeSize(.large)
        .buttonStyle(.plain)
        .padding(.spacingS)
        .background(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.thinMaterial), in: Circle())
        .padding(.spacingS)
        .help(isOn
            ? .app("View.CompareGitOverlay.ComparingVs \(diagram.comparisonGitRef ?? "")")
            : .app("View.CompareGitOverlay.CompareVsGit"))
        .accessibilityLabel(isOn
            ? .app("View.CompareGitOverlay.CompareVsGitActive")
            : .app("View.CompareGitOverlay.CompareVsGit"))
        .accessibilityIdentifier("delta.openButton")
        #if os(macOS)
        .popover(isPresented: $isPresented) {
            // Not `NavigationStack { ... .toolbar { clearButton } }`: on macOS, a `.toolbar` inside a
            // `NavigationStack` presented in a `.popover` renders its items in the presenting
            // window's own toolbar instead of inside the popover.
            VStack(alignment: .leading, spacing: .zero) {
                HStack {
                    Text(.app("View.CompareOverlayButton.CompareVsGit")).font(.headline)
                    Spacer()
                    CompareClearButton(diagram: diagram)
                }
                .padding()
                Divider()
                CompareGitPanel(diagram: diagram, onSelectChangedFileTypes: onSelectChangedFileTypes)
            }
        }
        #endif
    }
}

/// "Clear" is the counterpart to picking a ref from the list, not one more list item, so it lives in
/// the panel's header chrome rather than at the top of the scrollable content underneath.
struct CompareClearButton: View {
    let diagram: GeneratedDiagram
    @EnvironmentObject private var model: ProjectBrowserViewModel

    var body: some View {
        Button(.app("View.CompareOverlayButton.Clear")) {
            model.updateComparisonGitRef(diagramID: diagram.id, ref: nil)
        }
        .disabled(diagram.comparisonGitRef == nil)
        .accessibilityIdentifier("delta.clearButton")
    }
}
/// Comparison controls: comparing the codebase's current working tree against a git revision
/// (`HEAD`, a branch, a SHA, …) and colour-coding the added/removed/changed elements. Reads and
/// writes the diagram's `comparisonGitRef` through the model; the actual snapshot load is driven
/// by the host view's `.task`. Presented inside `CompareOverlayButton`'s popover/sheet.
struct CompareGitPanel: View {
    let diagram: GeneratedDiagram
    var onSelectChangedFileTypes: ((Set<String>) -> Void)?
    @EnvironmentObject var model: ProjectBrowserViewModel
    @State private var availableRefs: [GitCheckout.Ref] = []
    @State private var changeRequests: [ChangeRequest] = []
    @State private var fullHistoryPhase: AsyncOperationPhase = .idle
    @State private var pickerPhase: AsyncOperationPhase = .idle
    /// Retrying replaces this, so the reload runs as the view's own `.task` — cancelled when the
    /// popover or sheet goes away, which a `Task { }` started from the button would not be.
    @State private var pickerReloadToken = UUID()
    @State private var isEditingCustomRef = false
    @State private var customRefText = ""

    private var state: ComparePanelState {
        ComparePanelState(
            refs: availableRefs,
            changeRequests: changeRequests,
            comparisonGitRef: diagram.comparisonGitRef,
            comparisonBaseRef: diagram.comparisonBaseRef,
            hasOldArtifact: model.comparisonArtifact(for: diagram) != nil,
            hasNewArtifact: model.comparisonNewArtifact(for: diagram) != nil,
            error: model.comparisonError)
    }

    var body: some View {
        let state = state
        VStack(alignment: .leading, spacing: .zero) {
            List(state.rows) { row in
                Button {
                    select(row)
                } label: {
                    rowLabel(row, isSelected: row == state.selectedRow)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(row.accessibilityTitle)
                .accessibilityValue(row.kindLabel ?? Text(verbatim: ""))
                .accessibilityAddTraits(row == state.selectedRow ? .isSelected : [])
                .accessibilityIdentifier("delta.ref.\(row.testIdentifier)")
            }
            .listStyle(.plain)
            .task(id: pickerReloadToken) { await loadPicker() }
            .frame(minHeight: 150, maxHeight: 260)
            // The nav-bar Clear button lives on a different view instance and can't reach
            // `isEditingCustomRef` directly, so sync it from the model when comparison turns off.
            .onChange(of: diagram.comparisonGitRef) { _, newValue in
                if newValue == nil { isEditingCustomRef = false }
            }

            VStack(alignment: .leading, spacing: .spacingM) {
                pickerStatus
                if isEditingCustomRef {
                    TextField(text: $customRefText) {
                        Text(.app("View.CompareGitPanel.RefPlaceholder"))
                    }
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.updateComparisonGitRef(diagramID: diagram.id, ref: customRefText) }
                    .accessibilityIdentifier("delta.customRefField")
                }

                if let status = state.status {
                    legend
                    statusLine(status)
                }
                if state.isFullyLoaded {
                    changedFilesSection
                    findingsSections
                }
            }
            .padding(.spacingL)
        }
        .frame(minWidth: 260, alignment: .leading)
        .task(id: "\(diagram.id)|\(diagram.comparisonGitRef ?? "")|\(diagram.comparisonBaseRef ?? "")") {
            await model.ensureComparisonAnalysisLoaded(for: diagram)
        }
    }

    private func rowLabel(_ row: ComparePanelState.Row, isSelected: Bool) -> some View {
        HStack {
            rowTitle(row)
            Spacer()
            if let kind = row.kindLabel {
                kind
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func rowTitle(_ row: ComparePanelState.Row) -> some View {
        switch row {
        case .head:
            Text(verbatim: "HEAD")
        case .ref(let ref):
            Text(verbatim: ref.name)
        case .changeRequest(let pullRequest):
            VStack(alignment: .leading, spacing: .spacingXXS) {
                Text(verbatim: "#\(pullRequest.number) \(pullRequest.title)")
                    .lineLimit(2)
                pullRequest.pickerDetail
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        case .custom:
            Text(.app("View.CompareGitPanel.Custom"))
        }
    }

    private func select(_ row: ComparePanelState.Row) {
        switch row {
        case .head:
            isEditingCustomRef = false
            model.updateComparisonGitRef(diagramID: diagram.id, ref: "HEAD")
        case .ref(let ref):
            isEditingCustomRef = false
            model.updateComparisonGitRef(diagramID: diagram.id, ref: ref.name)
        case .changeRequest(let pullRequest):
            isEditingCustomRef = false
            model.selectComparisonPullRequest(
                diagramID: diagram.id, base: pullRequest.baseRef, head: pullRequest.headRef)
        case .custom:
            customRefText = diagram.comparisonGitRef ?? "HEAD"
            isEditingCustomRef = true
        }
    }

    @ViewBuilder
    private func statusLine(_ status: ComparePanelState.Status) -> some View {
        switch status {
        case .failed(let error):
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
                .accessibilityIdentifier("delta.error")
            if model.comparisonNeedsFullHistory, let codebase = model.codebase(for: diagram.codebaseID),
               codebase.managedCheckout != nil, let remoteURL = codebase.repository?.remoteURL {
                FetchFullHistoryButton(
                    remoteURL: remoteURL, phase: $fullHistoryPhase, identifierPrefix: "delta.fullHistory"
                ) {
                    Task { await model.ensureComparisonLoaded(for: diagram) }
                }
            }
        case .loading:
            HStack(spacing: .spacingXS) {
                ProgressView().controlSize(.small)
                Text(.app("View.CompareGitPanel.Loading \(diagram.comparisonGitRef ?? "")"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // Distinguishes, for a UI test that times out waiting for "delta.loaded", "the panel is
            // genuinely still loading" (a real timing issue) from "the panel never reached a
            // recognizable comparison state at all" (a different bug) — both currently surface
            // identically as a bare timeout with `comparisonError` unset.
            .accessibilityIdentifier("delta.loading")
        case .loaded:
            Text(.app("View.CompareGitPanel.Loaded")).font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("delta.loaded")
        }
    }

    // MARK: - Changed Files

    private var currentArtifact: CodeArtifact? {
        model.comparisonNewArtifact(for: diagram) ?? model.artifact(for: diagram.codebaseID)
    }

    private var changedFiles: [CompareChangedFiles.FileEntry] {
        guard let old = model.comparisonArtifact(for: diagram), let new = currentArtifact else { return [] }
        let diff = ArtifactDiffer().diff(old: old, new: new)
        return CompareChangedFiles(diff: diff, oldArtifact: old, newArtifact: new).files
    }

    private var changedFilesSection: some View {
        DisclosureGroup(.app("View.CompareGitPanel.ChangedFiles \(changedFiles.count)")) {
            VStack(alignment: .leading, spacing: .spacingXS) {
                ForEach(changedFiles) { entry in
                    changedFileRow(entry)
                }
            }
        }
        .accessibilityIdentifier("delta.changedFilesSection")
    }

    private func changedFileRow(_ entry: CompareChangedFiles.FileEntry) -> some View {
        let reviewed = model.isComparisonFileReviewed(diagramID: diagram.id, filePath: entry.filePath)
        let codebase = model.codebase(for: diagram.codebaseID)
        let reference: CodeElementReference? = entry.typeIDs.count == 1
            ? entry.typeIDs.first.map { .type(id: $0) } : nil

        return HStack(spacing: .spacingXS) {
            Button {
                model.toggleComparisonFileReviewed(diagramID: diagram.id, filePath: entry.filePath)
            } label: {
                Image(systemName: reviewed ? "checkmark.square.fill" : "square")
                    .foregroundStyle(reviewed ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                reviewed
                    ? .app("View.CompareGitPanel.MarkFileNotReviewed \(entry.filePath)")
                    : .app("View.CompareGitPanel.MarkFileReviewed \(entry.filePath)"))
            .accessibilityIdentifier("delta.changedFile.reviewToggle.\(entry.filePath)")

            Text(verbatim: entry.filePath)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .openInCodeElement(reference, codebase: codebase, relativePath: entry.filePath)

            Spacer()

            if let onSelectChangedFileTypes {
                Button {
                    onSelectChangedFileTypes(entry.typeIDs)
                } label: {
                    Image(systemName: "scope")
                }
                .buttonStyle(.plain)
                .help(.app("View.CompareGitPanel.SelectChangedNodeS"))
                .accessibilityLabel(.app("View.CompareGitPanel.SelectChangedNodes \(entry.filePath)"))
                .accessibilityIdentifier("delta.changedFile.select.\(entry.filePath)")
            }
        }
        .accessibilityIdentifier("delta.changedFile.\(entry.filePath)")
    }

    /// Laid out by the enclosing stack rather than wrapped in one of its own: an idle phase has to
    /// take up no room at all, and a wrapper would still claim the stack's spacing.
    @ViewBuilder
    private var pickerStatus: some View {
        AsyncOperationStatusView(identifierPrefix: "delta.picker", phase: pickerPhase)
        if case .failed = pickerPhase {
            Button(.app("View.CompareGitPanel.Retry")) { pickerReloadToken = UUID() }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("delta.picker.retryButton")
        }
    }

    /// A failed refs or change-request load otherwise rendered exactly like a repository with
    /// nothing to compare against, with nothing to tap to try again.
    private func loadPicker() async {
        pickerPhase = .loading(.app("View.CompareGitPanel.LoadingRevisions"))
        do {
            availableRefs = try await model.comparisonRefs(codebaseID: diagram.codebaseID)
            changeRequests = try await loadedChangeRequests()
            pickerPhase = .loaded
        } catch {
            pickerPhase = .failed(String(localized: LoadFailure(error: error).message))
        }
    }

    /// Offered when the codebase's remote is on a host whose provider lists change requests —
    /// whether the app cloned it or it's a local folder tracking it. No remote and no stored
    /// credential are both "none to list" rather than a failure; a rejected or dropped request is
    /// thrown, since those are the ones the reader can act on.
    private func loadedChangeRequests() async throws -> [ChangeRequest] {
        guard let codebase = model.codebase(for: diagram.codebaseID),
              case .github(let owner, let repo) = codebase.repository?.host,
              let credential = GitHubTokenStore().load()?.credential
        else { return [] }
        return try await GitHubHostingServiceResolver().resolve().pullRequests(
            credential: credential, owner: owner, repo: repo)
    }
}

private extension ComparePanelState.Row {
    var kindLabel: Text? {
        switch self {
        case .custom:
            nil
        case .head:
            Text(verbatim: "HEAD")
        case .ref(let ref):
            if ref.kind == .branch {
                Text(.app("View.CompareGitPanel.KindBranch"))
            } else {
                Text(.app("View.CompareGitPanel.KindTag"))
            }
        case .changeRequest:
            Text(.app("View.CompareGitPanel.KindChangeRequest"))
        }
    }

    var accessibilityTitle: Text {
        switch self {
        case .head:
            Text(verbatim: "HEAD")
        case .ref(let ref):
            Text(verbatim: ref.name)
        case .changeRequest(let pullRequest):
            pullRequest.pickerAccessibilityLabel
        case .custom:
            Text(.app("View.CompareGitPanel.Custom"))
        }
    }
}

private extension ChangeRequest {
    var pickerDetail: Text {
        Text(.app("View.CompareGitPanel.ChangeRequestDetail \(authorLogin) \(headRef) \(baseRef)"))
    }

    var pickerAccessibilityLabel: Text {
        Text(.app("View.CompareGitPanel.ChangeRequestLabel \(number) \(title) \(authorLogin) \(headRef) \(baseRef)"))
    }
}
