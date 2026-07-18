import SwiftUI
import AcaiCore

/// A multi-select over `Relationship.Kind` producing the optional `kinds` set a rule restricts to.
/// "All kinds" maps to `nil` (no restriction); deselecting back to empty also collapses to `nil`.
struct RelationshipKindPicker: View {
    @Binding var kinds: Set<Relationship.Kind>?

    var body: some View {
        Menu {
            Button { kinds = nil } label: {
                Label("All kinds", systemImage: kinds == nil ? "checkmark" : "")
            }
            Divider()
            ForEach(Relationship.Kind.allCases, id: \.self) { kind in
                Button { toggle(kind) } label: {
                    Label(kind.rawValue, systemImage: isOn(kind) ? "checkmark" : "")
                }
            }
        } label: {
            Text(summary)
        }
        .fixedSize()
    }

    private var summary: String {
        guard let kinds, !kinds.isEmpty else { return "All kinds" }
        return "\(kinds.count) kind(s)"
    }

    private func isOn(_ kind: Relationship.Kind) -> Bool {
        kinds?.contains(kind) ?? false
    }

    private func toggle(_ kind: Relationship.Kind) {
        var set = kinds ?? []
        if set.contains(kind) { set.remove(kind) } else { set.insert(kind) }
        kinds = set.isEmpty ? nil : set
    }
}
