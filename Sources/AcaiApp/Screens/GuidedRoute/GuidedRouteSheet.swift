import SwiftUI

extension GuidedRoute.Stop.Kind {
    var title: LocalizedStringResource {
        switch self {
        case .entryPoint:
            .app("View.GuidedRouteSheet.EntryPoint")
        case .mostDependedUpon:
            .app("View.GuidedRouteSheet.MostDependedUpon")
        case .mostComplex:
            .app("View.GuidedRouteSheet.MostComplex")
        }
    }

    var stopDescription: LocalizedStringResource {
        switch self {
        case .entryPoint:
            .app("View.GuidedRouteSheet.EntryPointDescription")
        case .mostDependedUpon:
            .app("View.GuidedRouteSheet.MostDependedUponDescription")
        case .mostComplex:
            .app("View.GuidedRouteSheet.MostComplexDescription")
        }
    }

    var systemImage: String {
        switch self {
        case .entryPoint:
            "arrowshape.turn.up.forward"
        case .mostDependedUpon:
            "point.3.connected.trianglepath.dotted"
        case .mostComplex:
            "chart.line.uptrend.xyaxis"
        }
    }
}

/// The guided-route tour: one row per stop, each opening the diagram that actually shows what the
/// stop names — see `GuidedRouteBuilder`. Presented automatically once a codebase is indexed for the
/// first time (`ProjectBrowserViewModel.pendingGuidedRoute`), and re-runnable any time from the
/// codebase detail toolbar.
struct GuidedRouteSheet: View {
    let route: GuidedRoute
    @EnvironmentObject private var model: ProjectBrowserViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(route.stops) { stop in
                Button {
                    open(stop)
                } label: {
                    stopRow(stop)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("guidedRoute.stop.\(stop.kind.rawValue)")
            }
            .navigationTitle(.app("View.GuidedRouteSheet.Title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(.app("View.GuidedRouteSheet.NotNow")) { dismiss() }
                        .accessibilityIdentifier("guidedRoute.notNow")
                }
            }
            #if os(macOS)
            .frame(minWidth: 420, minHeight: 320)
            #endif
        }
    }

    private func stopRow(_ stop: GuidedRoute.Stop) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: stop.kind.systemImage)
                .font(.title3)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(localized: stop.kind.title)
                    .font(.headline)
                Text(verbatim: stop.subject)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(localized: stop.kind.stopDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private func open(_ stop: GuidedRoute.Stop) {
        guard let id = model.diagrams.add(to: route.projectID, codebaseID: route.codebaseID, content: stop.content)
        else { return }
        model.selection = .generatedDiagram(id)
        dismiss()
    }
}
