import SwiftUI

extension GuidedRouteStop.Kind {
    var title: LocalizedStringResource {
        switch self {
        case .entryPoint:
            .app("View.GuidedRouteCard.EntryPoint")
        case .mostDependedUpon:
            .app("View.GuidedRouteCard.MostDependedUpon")
        case .mostComplex:
            .app("View.GuidedRouteCard.MostComplex")
        }
    }

    var stopDescription: LocalizedStringResource {
        switch self {
        case .entryPoint:
            .app("View.GuidedRouteCard.EntryPointDescription")
        case .mostDependedUpon:
            .app("View.GuidedRouteCard.MostDependedUponDescription")
        case .mostComplex:
            .app("View.GuidedRouteCard.MostComplexDescription")
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

struct GuidedRouteCard: View {
    let projectID: UUID
    let codebaseID: UUID
    let stops: [GuidedRouteStop]
    @EnvironmentObject private var model: ProjectBrowserViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Label(.app("View.GuidedRouteCard.Title"), systemImage: "map")
                    .font(.headline)
                Spacer()
                Button {
                    model.editing.setGuidedRoute(.dismissed, codebaseID: codebaseID)
                } label: {
                    Label(.app("View.GuidedRouteCard.Hide"), systemImage: "xmark")
                }
                .accessibilityIdentifier("guidedRoute.hideButton")
            }
            if stops.isEmpty {
                Text(.app("View.GuidedRouteCard.EmptyState"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("guidedRoute.emptyState")
            } else {
                ForEach(stops) { stop in
                    stopButton(stop)
                }
            }
        }
        .padding(Spacing.m)
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("guidedRoute.card")
    }

    private func stopButton(_ stop: GuidedRouteStop) -> some View {
        Button {
            open(stop)
        } label: {
            HStack(alignment: .top, spacing: Spacing.m) {
                Image(systemName: stop.kind.systemImage)
                    .font(.title3)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs) {
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
                Image(systemName: "chevron.forward")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                open(stop)
            } label: {
                Label(.app("View.GuidedRouteCard.OpenStop"), systemImage: stop.kind.systemImage)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("guidedRoute.stop.\(stop.kind.rawValue)")
    }

    private func open(_ stop: GuidedRouteStop) {
        guard let id = model.diagrams.addOrReuse(to: projectID, codebaseID: codebaseID, content: stop.content)
        else { return }
        model.open(.generatedDiagram(id))
    }
}
