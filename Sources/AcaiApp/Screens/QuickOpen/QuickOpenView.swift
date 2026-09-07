import SwiftUI
import AcaiCore

/// Quick Open: one search box over every project's types/modules/methods/diagrams, resolving
/// a chosen result through the same `CodeElementReference` mechanism `CodeElementReference
/// +Resolution.swift` already provides for every other "Open in…" surface in the app — Quick Open
/// doesn't invent a second way to turn "a type" into "a diagram," it's just another entry point into
/// the one that already shipped.
///
/// Presented as a sheet on macOS (⌘K) and iPhone (a dedicated search button); embedded directly
/// above the Projects sidebar's `List` on iPad, where its results replace the project tree while a
/// query is active — "the sidebar tree optional rather than mandatory," per the design doc.
struct QuickOpenView: View {
    @EnvironmentObject private var model: ProjectBrowserViewModel
    /// `nil` when hosted inline (iPad) — there is nothing to dismiss; a sheet host passes its own
    /// `\.dismiss` action through so a chosen result can close the sheet after applying it.
    var dismissAction: (() -> Void)?

    @State private var query = ""
    @State private var allEntries: [QuickOpenEntry] = []
    @State private var isBuildingIndex = false
    @State private var searchTask: Task<Void, Never>?
    @State private var filteredEntries: [QuickOpenEntry] = []
    @FocusState private var isFieldFocused: Bool

    private var controller: QuickOpenController { QuickOpenController(model: model) }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            resultsList
        }
        .task { await buildIndex() }
        .onChange(of: query) { _, newValue in
            scheduleSearch(for: newValue)
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(text: $query) {
                Text(.app("View.QuickOpenView.SearchTypesModulesMethods"))
            }
            .textFieldStyle(.plain)
            .focused($isFieldFocused)
            .accessibilityIdentifier("quickOpen.searchField")
            .onAppear { isFieldFocused = true }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(.app("View.QuickOpenView.ClearSearch"))
            }
        }
        .padding(10)
    }

    @ViewBuilder
    private var resultsList: some View {
        if isBuildingIndex {
            ProgressView(.app("View.QuickOpenView.Indexing"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("quickOpen.loadingState")
        } else if query.isEmpty {
            ContentUnavailableView {
                Label(.app("View.QuickOpenView.SearchEverything"), systemImage: "magnifyingglass")
            } description: {
                Text(.app("View.QuickOpenView.FindTypeModuleMethod"))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("quickOpen.emptyState")
        } else if filteredEntries.isEmpty {
            ContentUnavailableView.search(text: query)
                .accessibilityIdentifier("quickOpen.noResultsState")
        } else {
            List(filteredEntries) { entry in
                QuickOpenResultRow(entry: entry, onSelect: { resolution in
                    controller.apply(resolution, entry: entry)
                    dismissAction?()
                })
                .accessibilityIdentifier("quickOpen.result.\(entry.id)")
            }
            #if os(macOS)
            .listStyle(.plain)
            #endif
        }
    }

    /// Builds the search index off the main actor — the real cost risk for Quick Open is
    /// re-scanning every codebase's artifact, not the keystrokes (those are handled by
    /// `scheduleSearch`'s debounce below). Runs once per presentation, not per query.
    private func buildIndex() async {
        isBuildingIndex = true
        defer { isBuildingIndex = false }
        let builder = QuickOpenIndexBuilder(
            projects: model.store.projects,
            artifacts: model.store.artifacts,
            generatedDiagrams: model.store.generatedDiagrams,
            freeformDiagrams: model.store.freeformDiagrams
        )
        allEntries = await Task.detached(priority: .userInitiated) { builder.entries() }.value
    }

    /// Debounces to the trailing edge of a short pause rather than filtering on every keystroke —
    /// cancels any still-pending search before scheduling the new one.
    private func scheduleSearch(for text: String) {
        searchTask?.cancel()
        guard !text.isEmpty else {
            filteredEntries = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            let matches = controller.filtered(allEntries, matching: text)
            guard !Task.isCancelled else { return }
            filteredEntries = matches
        }
    }
}

/// Wraps `QuickOpenView` for sheet presentation (macOS ⌘K, iPhone's dedicated search button, and
/// iPad's pinned search field, which opens this same sheet rather than filtering inline — see
/// `ProjectBrowserView`'s sidebar for why: one shared implementation of the search+resolve flow,
/// not a second, divergent inline variant). Supplies `dismissAction` from `\.dismiss` so choosing a
/// result closes the sheet.
struct QuickOpenSheetHost: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            QuickOpenView(dismissAction: { dismiss() })
                .navigationTitle(.app("View.QuickOpenSheetHost.QuickOpen"))
                #if os(iOS)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(.app("View.QuickOpenSheetHost.Cancel")) { dismiss() }
                            .accessibilityIdentifier("quickOpen.cancelButton")
                    }
                }
                #endif
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 360)
        #endif
    }
}

/// One Quick Open result row: tapping it applies the first (most relevant) resolution directly —
/// matching every other "Open in…" surface's "default action on tap-through" — with the remaining
/// resolutions available from a context menu, so every option stays discoverable, not just the
/// default one.
private struct QuickOpenResultRow: View {
    let entry: QuickOpenEntry
    let onSelect: (CodeElementResolution?) -> Void
    @EnvironmentObject private var model: ProjectBrowserViewModel

    private var resolutions: [CodeElementResolution] {
        guard let reference = entry.reference, let codebaseID = entry.codebaseID,
              let artifact = model.artifact(for: codebaseID)
        else { return [] }
        let scopedDiagrams = model.generatedDiagramsForProject(entry.projectID)
            .filter { $0.codebaseID == codebaseID }
        return reference.resolutions(in: artifact, existingDiagrams: scopedDiagrams)
    }

    var body: some View {
        Button {
            onSelect(resolutions.first)
        } label: {
            HStack {
                Image(systemName: entry.systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: entry.name)
                    Text(verbatim: entry.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            // Without this the trailing `Spacer()` is not hit-testable, so a row whose text is
            // shorter than the row is only tappable over the text itself — visible as a dead right
            // half on regular width, where rows are widest.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            ForEach(resolutions.dropFirst()) { resolution in
                Button {
                    onSelect(resolution)
                } label: {
                    Label(
                        .app("View.QuickOpenView.OpenIn \(String(localized: resolution.diagramType.title))"),
                        systemImage: resolution.diagramType.systemImage)
                }
            }
        }
    }
}
