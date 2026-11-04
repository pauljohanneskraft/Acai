import AcaiCore
import SwiftUI

extension NewCodebaseSheetContent {
    @ViewBuilder
    var projectRootsSection: some View {
        if sheet.discoveryPhase != .idle {
            Section {
                AsyncOperationStatusView(identifierPrefix: "newCodebase.rootDiscovery", phase: sheet.discoveryPhase)
            }
        }
        if sheet.plan.isOffered {
            Section {
                // Above the rows, so it stays reachable without scrolling in a short window.
                Toggle(isOn: $sheet.plan.combinesIntoOne) {
                    Text(.app("View.NewCodebaseSheet.CombineIntoOneCodebase"))
                }
                .accessibilityIdentifier("newCodebase.combineRootsToggle")
                .focused($focusedField, equals: .combineRoots)
                ForEach(sheet.plan.roots, id: \.path) { root in
                    rootRow(root)
                }
            } header: {
                Text(.app("View.NewCodebaseSheet.ProjectsFound \(sheet.plan.roots.count)"))
                    .accessibilityIdentifier("newCodebase.rootsHeader")
            } footer: {
                Text(localized: sheet.plan.combinesIntoOne
                    ? .app("View.NewCodebaseSheet.CombinedFooter")
                    : .app("View.NewCodebaseSheet.SplitFooter"))
            }
            .onChange(of: sheet.plan.roots.count, initial: true) { _, _ in
                focusedField = .combineRoots
            }
        }
    }

    /// Disabled rather than hidden while combining, so the list doesn't jump as the toggle flips.
    private func rootRow(_ root: CodeArtifact.DiscoveredRoot) -> some View {
        Toggle(isOn: Binding(
            get: { sheet.plan.isChecked(root) },
            set: { sheet.setRootChecked($0, for: root) }
        )) {
            VStack(alignment: .leading, spacing: .spacingXS) {
                Text(verbatim: root.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: rootSubtitle(root))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(sheet.plan.combinesIntoOne)
        .accessibilityIdentifier("newCodebase.root.\(root.path)")
        .accessibilityLabel(Text(.app("View.NewCodebaseSheet.IncludeProject \(root.path)")))
        .accessibilityValue(Text(verbatim: rootSubtitle(root)))
        .focused($focusedField, equals: .root(root.path))
    }

    private func rootSubtitle(_ root: CodeArtifact.DiscoveredRoot) -> String {
        let languages = root.languages.map(\.rawValue).joined(separator: ", ")
        let detector = root.isFallback
            ? String(localized: .app("View.NewCodebaseSheet.MatchedByFileExtension"))
            : root.detector
        return languages.isEmpty ? detector : "\(detector) · \(languages)"
    }
}
