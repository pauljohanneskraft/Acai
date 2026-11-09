import SwiftUI

/// A small filter field placed above a `Picker` whose option list can grow into the hundreds (e.g.
/// every type or method in a large codebase) — narrows the menu's contents before it's even opened,
/// instead of leaving the user to scroll a long alphabetized list.
struct PickerFilterField: View {
    @Binding var text: String
    var placeholder: String = "Filter…"

    /// What the field shows; `text` follows it once typing pauses, or at once when cleared.
    @State private var draft = ""

    private let debounce: Duration = .milliseconds(200)

    var body: some View {
        HStack(spacing: .spacingXS) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $draft)
                .textFieldStyle(.plain)
            if !draft.isEmpty {
                Button {
                    draft = ""
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.callout)
        .padding(.horizontal, .spacingXS)
        .padding(.vertical, .spacingXS)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
        .onAppear { draft = text }
        .task(id: draft) {
            guard draft != text else { return }
            guard (try? await Task.sleep(for: debounce)) != nil else { return }
            text = draft
        }
    }
}

extension Sequence<String> {
    /// Case-insensitive substring filter shared by every searchable picker's option list; empty
    /// `query` leaves the sequence unfiltered.
    func filtered(by query: String) -> [Element] {
        guard !query.isEmpty else { return Array(self) }
        return filter { $0.localizedCaseInsensitiveContains(query) }
    }

    /// Matches each option by the `label` it is shown with rather than by its own value.
    func filtered(by query: String, label: (Element) -> String) -> [Element] {
        guard !query.isEmpty else { return Array(self) }
        return filter { label($0).localizedCaseInsensitiveContains(query) }
    }
}
