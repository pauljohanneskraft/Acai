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

    var body: some View {
        HStack(spacing: 8) {
            fieldSection
            stepButtons
            dismissButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }

    // MARK: - Field + Match Count

    private var fieldSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(text: $query) {
                Text(.app("View.DiagramSearchBar.FindByName"))
            }
            .textFieldStyle(.plain)
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

    @ViewBuilder
    private var matchSummaryText: some View {
        if let matchSummary {
            Text(localized: matchSummary)
                .foregroundStyle(.secondary)
        } else {
            // Keeps the bar's width/height stable before the first keystroke rather than popping
            // in once there's something to report.
            Text(verbatim: " ")
        }
    }

    /// `nil` before the first keystroke — nothing has been searched for yet, which reads
    /// differently from a query that matched nothing.
    private var matchSummary: LocalizedStringResource? {
        guard !query.isEmpty else { return nil }
        return matchCount > 0
            ? .app("View.DiagramSearchBar.MatchCount \(matchCount)")
            : .app("View.DiagramSearchBar.NoMatches")
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
            .keyboardShortcut("g", modifiers: [.command, .shift])

            Button(action: onStepForward) {
                Image(systemName: "chevron.down")
            }
            .help(.app("View.DiagramSearchBar.NextMatch"))
            .accessibilityLabel(.app("View.DiagramSearchBar.NextMatch"))
            .accessibilityIdentifier("diagram.search.nextButton")
            .keyboardShortcut("g", modifiers: .command)
        }
        .buttonStyle(.plain)
        .disabled(matchCount == 0)
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
        .keyboardShortcut(.cancelAction)
    }
}
