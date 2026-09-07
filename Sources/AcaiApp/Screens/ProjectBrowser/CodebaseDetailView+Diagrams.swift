import SwiftUI
import AcaiCore

extension CodebaseDetailView {

    // MARK: - Card grid layout

    /// Flexible columns sized so `count` cards fill the full content width, wrapping to more rows only
    /// when the pane is too narrow to fit them all at `target` width. Capping the column count at the
    /// card count (rather than `.adaptive`) keeps the row full-width instead of leaving empty trailing
    /// columns when there are fewer cards than would fit.
    func cardColumns(count: Int, target: CGFloat = 200) -> [GridItem] {
        let usableWidth = contentWidth - 32 // outer .padding(.horizontal) on each side
        let fitting = max(1, Int((usableWidth + 12) / (target + 12)))
        let columns = max(1, min(count, fitting))
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: columns)
    }

    // MARK: - Diagrams

    func diagramsBar(codebase: Codebase, artifact: CodeArtifact) -> some View {
        // Cycle Diagram is deliberately excluded here: it has no meaningful content until a
        // specific cycle is chosen, so it isn't offered as a general "add a diagram" type — its one
        // entry point is "View as Diagram" on a Quality Check cycle violation row (see
        // `AnalysisReportViews.swift`'s `ViolationRowView`), which constructs it pre-scoped.
        let offeredTypes = DiagramType.allCases.filter { $0 != .cycleDiagram }
        return LazyVGrid(columns: cardColumns(count: offeredTypes.count), spacing: 12) {
            ForEach(offeredTypes) { type in
                diagramButton(codebase: codebase, type: type)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
        .onPreferenceChange(CardHeightPreferenceKey.self) { height in
            if abs(diagramCardHeight - height) > 0.5 { diagramCardHeight = height }
        }
    }

    private func diagramButton(codebase: Codebase, type: DiagramType) -> some View {
        Button {
            guard let projectID else { return }
            if type == .sequenceDiagram {
                sequenceConfigContext = ConfigContext(projectID: projectID, codebaseID: codebase.id)
                return
            }
            if type == .stateDiagram {
                stateConfigContext = ConfigContext(projectID: projectID, codebaseID: codebase.id)
                return
            }
            if type == .callGraph {
                callGraphConfigContext = ConfigContext(projectID: projectID, codebaseID: codebase.id)
                return
            }
            if let id = model.diagrams.add(
                to: projectID,
                codebaseID: codebase.id,
                content: GeneratedDiagram.Content(type: type)
            ) {
                model.selection = .generatedDiagram(id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: type.systemImage)
                    .font(.title2.bold())
                Text(localized: type.title)
                    .font(.title3.bold())
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: CardHeightPreferenceKey.self, value: proxy.size.height)
            })
            .frame(minHeight: diagramCardHeight > 0 ? diagramCardHeight : nil, alignment: .topLeading)
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("codebaseDetail.diagramButton.\(type.rawValue)")
    }
}
