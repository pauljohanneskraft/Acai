import AcaiCore
import SwiftUI

extension NewCodebaseSheetContent {
    /// The step that only exists when the picked folder holds more than one project: one codebase per
    /// root is the default, and combining them is the opt-in.
    @ViewBuilder
    var projectRootsSection: some View {
        if sheet.discoveryPhase.isInFlight {
            Section {
                AsyncOperationStatusView(identifierPrefix: "newCodebase.rootDiscovery", phase: sheet.discoveryPhase)
            }
        } else if sheet.plan.isOffered {
            Section {
                ForEach(sheet.plan.roots, id: \.path) { root in
                    rootRow(root)
                }
                Toggle(isOn: $sheet.plan.combinesIntoOne) {
                    Text(.app("View.NewCodebaseSheet.CombineIntoOneCodebase"))
                }
                .accessibilityIdentifier("newCodebase.combineRootsToggle")
                .focused($focusedField, equals: .combineRoots)
            } header: {
                Text(.app("View.NewCodebaseSheet.ProjectsFound \(sheet.plan.roots.count)"))
                    .accessibilityIdentifier("newCodebase.rootsHeader")
            } footer: {
                Text(localized: sheet.plan.combinesIntoOne
                    ? .app("View.NewCodebaseSheet.CombinedFooter")
                    : .app("View.NewCodebaseSheet.SplitFooter"))
            }
        }
    }

    /// Disabled rather than hidden while combining, so the roots stay readable as what *would* be
    /// split and the row count doesn't jump as the toggle flips.
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

    /// The detector's type name and the languages it claimed — parser output, so never translated.
    /// A fallback root was matched by file extension because no build system claimed it, which is
    /// worth saying rather than naming `FallbackDetector`.
    private func rootSubtitle(_ root: CodeArtifact.DiscoveredRoot) -> String {
        let languages = root.languages.map(\.rawValue).joined(separator: ", ")
        let detector = root.isFallback
            ? String(localized: .app("View.NewCodebaseSheet.MatchedByFileExtension"))
            : root.detector
        return languages.isEmpty ? detector : "\(detector) · \(languages)"
    }
}
