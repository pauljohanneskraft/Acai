import SwiftUI

extension ProjectBrowserView {
    #if !os(macOS)
    /// Styled like a search field, but taps open the same shared `QuickOpenSheetHost` macOS's ⌘K
    /// and iPhone's dedicated button also use, rather than a second inline variant.
    var quickOpenSearchFieldProxy: some View {
        Button {
            quickOpenPresenter.isPresented = true
        } label: {
            HStack {
                Image(systemName: "magnifyingglass")
                Text(.app("View.ProjectBrowserView.SearchTypesModulesMethods"))
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
