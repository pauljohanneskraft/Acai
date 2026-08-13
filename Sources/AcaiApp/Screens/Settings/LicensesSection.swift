import SwiftUI

struct LicensesSection: View {
    @State private var dependencies: [DependencyLicense] = []
    @State private var loadError: LicenseLoadFailure?

    var body: some View {
        Group {
            if dependencies.isEmpty && loadError == nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("licenses.loadingIndicator")
            } else {
                ForEach(dependencies) { dependency in
                    DisclosureGroup {
                        licenseDetail(dependency)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dependency.name)
                            Text(dependency.licenseIdentifier)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("licenses.row.\(dependency.name)")
                    .accessibilityLabel("\(dependency.name), \(dependency.licenseIdentifier) license")
                }
            }
        }
        .task { await load() }
        .alert(item: $loadError) { failure in
            Alert(
                title: Text("Something went wrong"),
                message: Text(failure.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @ViewBuilder
    private func licenseDetail(_ dependency: DependencyLicense) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let notes = dependency.notes {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("licenses.notes.\(dependency.name)")
            }
            ScrollView {
                Text(dependency.licenseText)
                    .font(.caption.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 220)
            .accessibilityIdentifier("licenses.text.\(dependency.name)")
        }
        .padding(.top, 4)
    }

    private func load() async {
        let catalog = LicenseCatalog()
        do {
            dependencies = try await Task.detached(priority: .userInitiated) {
                try catalog.load()
            }.value
        } catch {
            loadError = LicenseLoadFailure(message: error.localizedDescription)
        }
    }
}

private struct LicenseLoadFailure: Identifiable {
    let id = UUID()
    let message: String
}
