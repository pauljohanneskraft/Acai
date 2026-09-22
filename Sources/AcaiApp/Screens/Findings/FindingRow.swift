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
    /// `nil` when `finding.cycle` is `nil` (every non-cycle finding), or when this row is shown
    /// somewhere with no project context to create a diagram in — mirrors
    /// `ViolationRowView.onViewAsDiagram`'s rationale.
    var onOpenCycle: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            summary
                .openInCodeElement(finding.reference, codebase: codebase, relativePath: finding.location?.filePath)
            HStack(spacing: Spacing.m) {
                if let codebase, let location = finding.location {
                    ViewSourceButton(codebase: codebase, relativePath: location.filePath)
                }
                if finding.cycle != nil, let onOpenCycle {
                    Button(action: onOpenCycle) {
                        Label(.app("View.FindingRow.ViewDiagram"), systemImage: "arrow.triangle.2.circlepath")
                    }
                    .accessibilityIdentifier("findings.row.viewAsDiagramButton")
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
        .padding(Spacing.s)
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
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.s) {
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
            .padding(.horizontal, Spacing.xs).padding(.vertical, Spacing.xxs)
            .background(tint.opacity(0.12))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }
}
