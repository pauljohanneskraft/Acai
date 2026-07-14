import SwiftUI

/// A small filter field placed above a `Picker` whose option list can grow into the hundreds (e.g.
/// every type or method in a large codebase) — narrows the menu's contents before it's even opened,
/// instead of leaving the user to scroll a long alphabetized list.
struct PickerFilterField: View {
    @Binding var text: String
    var placeholder: String = "Filter…"

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.callout)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
    }
}

extension Sequence<String> {
    /// Case-insensitive substring filter shared by every searchable picker's option list; empty
    /// `query` leaves the sequence unfiltered.
    func filtered(by query: String) -> [Element] {
        guard !query.isEmpty else { return Array(self) }
        return filter { $0.localizedCaseInsensitiveContains(query) }
    }
}
