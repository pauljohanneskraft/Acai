import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Surfaces the "Export CI Check" action offered next to `QualityCheckSection`: the `acai quality`
/// invocation for this codebase's configured rules file, as a copyable shell command and a
/// ready-to-paste GitHub Actions step.
struct CIQualityCheckExportSheet: View {
    let codebaseName: String
    let invocation: CIQualityCheckInvocation

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if invocation.needsExportNote {
                        QualityCheckPlaceholder(
                            text: .app("View.CIQualityCheckExportSheet.RulesFileOutsideCodebase \(codebaseName)"),
                            systemImage: "exclamationmark.triangle")
                    }
                    snippetSection(
                        title: .app("View.CIQualityCheckExportSheet.ShellCommand"),
                        caption: .app("View.CIQualityCheckExportSheet.RunsAgainstCurrentLocation"),
                        code: invocation.shellCommand,
                        identifier: "ciCheckExport.shellCommand")
                    snippetSection(
                        title: .app("View.CIQualityCheckExportSheet.GitHubActionsStep"),
                        caption: .app("View.CIQualityCheckExportSheet.PasteIntoJob"),
                        code: invocation.gitHubActionsStep,
                        identifier: "ciCheckExport.actionsStep")
                }
                .padding()
            }
            #if os(macOS)
            .frame(minWidth: 480, idealWidth: 560, maxWidth: 720, minHeight: 360)
            #endif
            .navigationTitle(.app("View.CIQualityCheckExportSheet.ExportCICheck"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(.app("View.CIQualityCheckExportSheet.Done")) { dismiss() }
                }
            }
        }
    }

    private func snippetSection(
        title: LocalizedStringResource, caption: LocalizedStringResource, code: String, identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localized: title).font(.headline)
            Text(localized: caption).font(.caption).foregroundStyle(.secondary)
            Text(verbatim: code)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityIdentifier(identifier)
            Button(.app("View.CIQualityCheckExportSheet.Copy")) { copyToClipboard(code) }
                .accessibilityIdentifier("\(identifier).copyButton")
        }
    }

    private func copyToClipboard(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}
