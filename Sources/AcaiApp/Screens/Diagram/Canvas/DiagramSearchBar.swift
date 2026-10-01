import SwiftUI

/// The "find in diagram" bar: a text field, a match-count label, and step controls, presented as a
/// floating overlay over a diagram's canvas. Deliberately built on plain bindings/closures rather
/// than a `CanvasInteraction` model, so any diagram type can drop it in without adopting a shared
/// search protocol.
struct DiagramSearchBar: View {
    @Binding var query: String
    let matchCount: Int
    var isFocused: FocusState<Bool>.Binding
    let onStepForward: () -> Void
    let onStepBackward: () -> Void
    let onDismiss: () -> Void

    #if os(iOS)
    /// Read once per process: the field re-renders on every keystroke, and the environment a fixture
    /// is declared in cannot change while the app runs.
    private static let hidesCaret = UITestFixtureResolver().resolveBaseDir() != nil
    #endif

    var body: some View {
        HStack(spacing: .spacingS) {
            fieldSection
            stepButtons
            dismissButton
        }
        .padding(.horizontal, .spacingS)
        .padding(.vertical, .spacingXS)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }

    // MARK: - Field + Match Count

    private var fieldSection: some View {
        HStack(spacing: .spacingS) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(text: $query) {
                Text(.app("View.DiagramSearchBar.FindByName"))
            }
            .textFieldStyle(.plain)
            // Type names aren't prose: a capitalised or "corrected" query finds the wrong node.
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            // SwiftUI's tint overrides `AcaiRootScene`'s caret hiding, and a blinking caret is per-run
            // content in a UI-test screenshot. Inert in release, where no fixture is set.
            .tint(Self.hidesCaret ? .clear : nil)
            #endif
            .frame(minWidth: 140)
            .focused(isFocused)
            // Setting this from the toolbar action that reveals the bar races the field's own
            // creation (it doesn't exist in the hierarchy yet, so the focus request is dropped) —
            // same fix QuickOpenView's search field already uses for the same reason.
            .onAppear { isFocused.wrappedValue = true }
            .onSubmit(onStepForward)
            .accessibilityIdentifier("diagram.search.field")

            matchSummaryText
                .font(.caption)
                .frame(minWidth: 64, alignment: .leading)
                .accessibilityIdentifier("diagram.search.matchSummary")
        }
    }

    private var summary: DiagramSearchSummary {
        DiagramSearchSummary(query: query, matchCount: matchCount)
    }

    @ViewBuilder
    private var matchSummaryText: some View {
        switch summary.message {
        case .matches(let count):
            Text(.app("View.DiagramSearchBar.MatchCount \(count)"))
                .foregroundStyle(.secondary)
        case .noMatches:
            Text(.app("View.DiagramSearchBar.NoMatches"))
                .foregroundStyle(.secondary)
        case nil:
            // Keeps the bar's width/height stable before the first keystroke rather than popping
            // in once there's something to report.
            Text(verbatim: " ")
        }
    }

    // MARK: - Step Controls

    private var stepButtons: some View {
        Group {
            Button(action: onStepBackward) {
                Image(systemName: "chevron.up")
            }
            .help(.app("View.DiagramSearchBar.PreviousMatch"))
            .accessibilityLabel(.app("View.DiagramSearchBar.PreviousMatch"))
            .accessibilityIdentifier("diagram.search.previousButton")
            .keyboardShortcut(.previousMatch)

            Button(action: onStepForward) {
                Image(systemName: "chevron.down")
            }
            .help(.app("View.DiagramSearchBar.NextMatch"))
            .accessibilityLabel(.app("View.DiagramSearchBar.NextMatch"))
            .accessibilityIdentifier("diagram.search.nextButton")
            .keyboardShortcut(.nextMatch)
        }
        .buttonStyle(.plain)
        .disabled(!summary.canStep)
    }

    // MARK: - Dismiss

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark.circle.fill")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(.app("View.DiagramSearchBar.Close"))
        .accessibilityLabel(.app("View.DiagramSearchBar.Close"))
        .accessibilityIdentifier("diagram.search.dismissButton")
        .keyboardShortcut(.closeFind)
    }
}
