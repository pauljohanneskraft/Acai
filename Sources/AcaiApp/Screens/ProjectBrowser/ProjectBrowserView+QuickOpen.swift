import SwiftUI

// iPad's Quick Open search-field proxy — carved out of `ProjectBrowserView` to keep that file
// under the project's file-length limit, matching how `+Repositories.swift`/`+SidebarRows.swift`
// already split that screen's own concerns into extensions.
extension ProjectBrowserView {
    #if !os(macOS)
    /// A tap-to-open proxy for Quick Open, styled like a search field so it reads as "search lives
    /// here" at a glance, but opening the same shared `QuickOpenSheetHost` macOS's ⌘K and
    /// iPhone's dedicated button also use — one implementation of the search+resolve flow, not a
    /// second inline variant duplicating it.
    var quickOpenSearchFieldProxy: some View {
        Button {
            quickOpenPresenter.isPresented = true
        } label: {
            HStack {
                Image(systemName: "magnifyingglass")
                Text("Search types, modules, methods, diagrams…")
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sidebar.quickOpenField")
    }
    #endif
}
