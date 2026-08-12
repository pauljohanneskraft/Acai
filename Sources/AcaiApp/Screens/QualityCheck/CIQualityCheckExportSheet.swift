import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Surfaces the "Export CI Check" action offered next to `QualityCheckSection`: the exact `acai
/// quality` invocation for this codebase's configured rules file, as a copyable shell command and
/// a ready-to-paste GitHub Actions step. No new engine capability — this only formats an
/// invocation string from data the app already has (see `CIQualityCheckInvocation`).
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
                            text: "This rules file isn't inside \(codebaseName)'s own folder, so a CI "
                                + "runner's checkout won't have it. Commit a copy into the repository "
                                + "(e.g. as quality.yml) before using the snippet below in CI.",
                            systemImage: "exclamationmark.triangle")
                    }
                    snippetSection(
                        title: "Shell command",
                        caption: "Runs against this codebase's current location.",
                        code: invocation.shellCommand,
                        identifier: "ciCheckExport.shellCommand")
                    snippetSection(
                        title: "GitHub Actions step",
                        caption: "Paste into a job that already checks out the repository.",
                        code: invocation.gitHubActionsStep,
                        identifier: "ciCheckExport.actionsStep")
                }
                .padding()
            }
            #if os(macOS)
            .frame(minWidth: 480, idealWidth: 560, maxWidth: 720, minHeight: 360)
            #endif
            .navigationTitle("Export CI Check")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func snippetSection(title: String, caption: String, code: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(caption).font(.caption).foregroundStyle(.secondary)
            Text(code)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityIdentifier(identifier)
            Button("Copy") { copyToClipboard(code) }
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
