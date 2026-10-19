import SwiftUI

extension FindingsView {
    func filterBar(project: Project) -> some View {
        VStack(alignment: .leading, spacing: .spacingS) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: .spacingS) {
                    ForEach(Finding.Kind.allCases) { kind in
                        kindChip(kind)
                    }
                }
            }
            HStack {
                Picker(.app("View.FindingsView.Codebase"), selection: $list.codebaseID) {
                    Text(.app("View.FindingsView.AllCodebases")).tag(UUID?.none)
                    ForEach(project.codebases.sorted { $0.name < $1.name }) { codebase in
                        Text(verbatim: codebase.name).tag(Optional(codebase.id))
                    }
                }
                .accessibilityIdentifier("findings.codebaseFilter")
                Spacer()
                Toggle(.app("View.FindingsView.ShowSuppressedToo"), isOn: $list.showSuppressed)
                    .toggleStyle(.button)
                    .accessibilityIdentifier("findings.showSuppressedToggle")
            }
        }
        .padding(.horizontal)
        .padding(.top, .spacingS)
    }

    /// Shown only while a filter is actually narrowing the list, so it never offers to undo nothing.
    var clearFiltersButton: some View {
        Button {
            list = list.clearingFilters()
        } label: {
            Label(.app("View.FindingsView.ClearFilters"), systemImage: "line.3.horizontal.decrease.circle")
        }
        .accessibilityIdentifier("findings.clearFiltersButton")
    }

    private func kindChip(_ kind: Finding.Kind) -> some View {
        let isSelected = list.kinds.contains(kind)
        return Button {
            list = list.toggling(kind)
        } label: {
            Label(kind.title, systemImage: kind.systemImage)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, .spacingS).padding(.vertical, .spacingXS)
                .background(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("findings.kindFilter.\(kind.rawValue)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
