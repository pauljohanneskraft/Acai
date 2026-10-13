import SwiftUI

struct LicensesSection: View {
    @State private var dependencies: [DependencyLicense] = []
    @State private var phase: AsyncOperationPhase = .loading(.app("View.LicensesSection.LoadingLicenses"))
    @State private var attempt = 0

    var body: some View {
        Group {
            status
            if case .loaded = phase {
                if dependencies.isEmpty {
                    emptyState
                } else {
                    ForEach(dependencies) { dependency in
                        licenseRow(dependency)
                    }
                }
            }
        }
        .task(id: attempt) { await load() }
    }

    private var status: some View {
        HStack(spacing: .spacingS) {
            AsyncOperationStatusView(identifierPrefix: "licenses", phase: phase)
            if case .failed = phase {
                Button {
                    attempt += 1
                } label: {
                    Label(.app("View.LicensesSection.Retry"), systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("licenses.retryButton")
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(.app("View.LicensesSection.NoLicensesListed"), systemImage: "doc.plaintext")
        } description: {
            Text(.app("View.LicensesSection.NoLicensesDetail"))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("licenses.emptyState")
    }

    private func licenseRow(_ dependency: DependencyLicense) -> some View {
        DisclosureGroup {
            licenseDetail(dependency)
        } label: {
            VStack(alignment: .leading, spacing: .spacingXXS) {
                Text(verbatim: dependency.name)
                Text(verbatim: dependency.licenseIdentifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("licenses.row.\(dependency.name)")
        .accessibilityLabel(
            .app("View.LicensesSection.License \(dependency.name) \(dependency.licenseIdentifier)")
        )
    }

    @ViewBuilder
    private func licenseDetail(_ dependency: DependencyLicense) -> some View {
        VStack(alignment: .leading, spacing: .spacingS) {
            if let notes = dependency.notes {
                Text(verbatim: notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("licenses.notes.\(dependency.name)")
            }
            ScrollView {
                Text(verbatim: dependency.licenseText)
                    .font(.caption.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 220)
            .accessibilityIdentifier("licenses.text.\(dependency.name)")
        }
        .padding(.top, .spacingXS)
    }

    private func load() async {
        phase = .loading(.app("View.LicensesSection.LoadingLicenses"))
        let catalog = LicenseCatalog()
        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                try catalog.load()
            }.value
            guard !Task.isCancelled else { return }
            dependencies = loaded
            phase = .loaded
        } catch {
            guard !Task.isCancelled else { return }
            dependencies = []
            phase = .failed(error.localizedDescription)
        }
    }
}
