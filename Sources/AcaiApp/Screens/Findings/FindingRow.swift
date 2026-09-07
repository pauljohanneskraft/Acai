import SwiftUI

/// One row in the project-level Findings list — kind/severity badges, the "Open in…" resolution,
/// "View Source", and, when suppression is available, a "Suppress"/"Un-suppress" action.
struct FindingRow: View {
    let finding: Finding
    let codebase: Codebase?
    /// `nil` hides the suppression action entirely — not wired in, or this row is already shown
    /// under "show suppressed too" without a store to act through.
    var isSuppressed: Bool = false
    var onToggleSuppressed: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            summary
                .openInCodeElement(finding.reference, codebase: codebase, relativePath: finding.location?.filePath)
            HStack(spacing: 12) {
                if let codebase, let location = finding.location {
                    ViewSourceButton(codebase: codebase, relativePath: location.filePath)
                }
                if let onToggleSuppressed {
                    Button(action: onToggleSuppressed) {
                        Label(
                            isSuppressed ? "Show" : "Suppress",
                            systemImage: isSuppressed ? "eye" : "eye.slash")
                    }
                    .accessibilityIdentifier(
                        isSuppressed ? "findings.row.unsuppressButton" : "findings.row.suppressButton")
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .opacity(isSuppressed ? 0.6 : 1)
        // Without `.contain`, this row's own `.accessibilityIdentifier` bleeds down onto every
        // nested button (`ViewSourceButton`, "Suppress") and overwrites each one's own identifier
        // with this row's.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("findings.row.\(finding.id)")
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                badge(text: finding.kind.title, systemImage: finding.kind.systemImage, tint: .secondary)
                badge(text: finding.severity.title, systemImage: finding.severity.systemImage, tint: severityTint)
                Spacer()
                Text(verbatim: finding.codebaseName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(verbatim: finding.title)
                .font(.callout.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: finding.message)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let location = finding.location {
                Text(verbatim: "\(location.filePath):\(location.line)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var severityTint: Color {
        switch finding.severity {
        case .info:
            .secondary
        case .warning:
            .orange
        case .critical:
            .red
        }
    }

    private func badge(text: LocalizedStringResource, systemImage: String, tint: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.monospaced())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(tint.opacity(0.12))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }
}
