import Foundation
import SwiftUI
import AcaiCore
import AcaiDiagram
import AcaiDiff
import AcaiQuality
import AcaiRender

/// Builds a `StateDiagram` from the stored variable configuration, then applies the
/// configuration's `Selector` filter if any — an instantiated value with instance methods (never
/// a static-function namespace) that `StateDiagramViewModel` delegates diagram generation to,
/// including from its own `init`, before `self` is fully initialized and so before any of the
/// view model's own instance methods could be called.
private struct StateDiagramGenerator {
    let artifact: CodeArtifact
    let configuration: StateDiagramConfiguration?

    func generate() -> Result<StateDiagram, StateDiagramAnalysisError>? {
        guard let configuration else { return nil }
        do {
            let diagram = try StateDiagramBuilder(configuration: configuration)
                .build(from: artifact.resolvingExtensions())
            guard let filter = configuration.filter else { return .success(diagram) }
            return .success(filtered(diagram, by: filter))
        } catch let error as StateDiagramAnalysisError {
            return .failure(error)
        } catch {
            // `StateDiagramBuilder.build` only throws `StateDiagramAnalysisError`, so this is
            // unreachable; trap it loudly in debug rather than reporting a misleading "no
            // assignments" failure if that contract ever changes.
            assertionFailure("unexpected state-diagram analysis error: \(error)")
            return .failure(.noAssignments(variableName: configuration.variableName))
        }
    }

    /// Drops states `filter` doesn't match by name (and transitions touching them) — except the
    /// initial pseudo-state (`StateDiagram.State.Kind.initial`), which stays regardless: it has no
    /// name to match against, and hiding it would break every transition chain's visible starting
    /// point.
    private func filtered(_ diagram: StateDiagram, by filter: AcaiQuality.Selector) -> StateDiagram {
        let keptIDs = Set(diagram.states.filter { state in
            state.kind == .initial || filter.matchesName(state.name)
        }.map(\.id))
        return StateDiagram(
            title: diagram.title,
            states: diagram.states.filter { keptIDs.contains($0.id) },
            transitions: diagram.transitions.filter { keptIDs.contains($0.from) && keptIDs.contains($0.to) }
        )
    }
}

/// Backs the movement-only state diagram view. The `StateDiagram` regenerates from the stored
/// variable configuration, so it tracks the code; analysis failures surface as a typed error
/// rather than an empty canvas. Dragged node positions are the only editable, undoable state.
@MainActor
final class StateDiagramViewModel: ObservableObject, LayoutBackedCanvas {
    let artifact: CodeArtifact
    private let comparisonArtifact: CodeArtifact?

    /// `nil` while the diagram has no state-variable spec chosen yet.
    @Published private(set) var result: Result<StateDiagram, StateDiagramAnalysisError>?
    @Published var positionOverrides: [String: CGPoint] = [:]
    @Published var selectedNodeIDs: Set<String> = []
    @Published var isMultiSelectActive = false
    /// The selected transition, keyed by its position in `diagram.transitions` (also
    /// `StateLayoutModel.EdgeLayout.id`) — the Inspector tab. Positional, not a stable identity;
    /// safe because `applyConfiguration` always clears this alongside the node selection.
    @Published var selectedTransitionID: Int?

    private(set) var configuration: StateDiagramConfiguration?
    private var diff: StateDiagramDiff?

    let history = DiagramHistoryManager<[String: CGPoint]>()

    // MARK: - Init

    init(
        artifact: CodeArtifact,
        configuration: StateDiagramConfiguration?,
        restoredPositions: [String: CGPoint] = [:],
        comparisonArtifact: CodeArtifact? = nil
    ) {
        self.artifact = artifact
        self.comparisonArtifact = comparisonArtifact
        self.configuration = configuration
        self.positionOverrides = restoredPositions
        self.result = nil
        rebuild(configuration: configuration)
    }

    /// In delta mode, renders the union of both revisions (via `StateDiagramDiff`) so removed
    /// states/transitions still appear and can be tinted. Falls back to the plain working-tree
    /// result — without a diff — when the comparison revision fails its own analysis (e.g. the
    /// chosen variable didn't exist yet): there's nothing to diff against, but the new result is
    /// still shown rather than reporting a spurious failure.
    private func rebuild(configuration: StateDiagramConfiguration?) {
        let newResult = StateDiagramGenerator(artifact: artifact, configuration: configuration).generate()
        guard let comparisonArtifact, case .success(let new) = newResult else {
            diff = nil
            result = newResult
            return
        }
        guard case .success(let old) = StateDiagramGenerator(
            artifact: comparisonArtifact, configuration: configuration
        ).generate() else {
            diff = nil
            result = newResult
            return
        }
        let diff = StateDiagramDiff(old: old, new: new)
        self.diff = diff
        result = .success(diff.union)
    }

    func applyConfiguration(_ newConfiguration: StateDiagramConfiguration) {
        configuration = newConfiguration
        rebuild(configuration: newConfiguration)
        positionOverrides = [:]
        selectedNodeIDs = []
        selectedTransitionID = nil
        history.clear()
    }

    /// Re-derives the diagram for a new filter, keeping the position overrides and undo history —
    /// unlike `applyConfiguration`, filtering only removes states/transitions, it never
    /// repositions a surviving one.
    func applyFilter(_ filter: AcaiQuality.Selector?) {
        configuration?.filter = filter
        rebuild(configuration: configuration)
    }

    var isDeltaMode: Bool { diff != nil }

    /// Non-color complement to `transitionDeltaColor(_:)`. `nil` when unchanged or not in delta mode.
    func stateDeltaStatus(_ id: String) -> DeltaStatus? {
        guard let diff else { return nil }
        let status = diff.status(ofState: id)
        return status == .unchanged ? nil : status
    }

    /// Feeds `StateEnsembleView`'s `edgeColor` hook, keyed on `StateLayoutModel.EdgeLayout.id` —
    /// the index into `diagram.transitions` both the layout and the union diagram share.
    func transitionDeltaColor(_ edge: StateLayoutModel.EdgeLayout) -> Color? {
        guard let diff, let transitions = diagram?.transitions, transitions.indices.contains(edge.id),
              let hex = diff.status(of: transitions[edge.id]).deltaHex
        else { return nil }
        return Color(hex: hex)
    }

    func transitionDeltaStatus(_ transition: StateDiagram.Transition) -> DeltaStatus? {
        guard let diff else { return nil }
        let status = diff.status(of: transition)
        return status == .unchanged ? nil : status
    }

    func selectionWillReplace() {
        selectedTransitionID = nil
    }

    func stateName(_ id: String) -> String? {
        diagram?.states.first { $0.id == id }?.name
    }

    var diagram: StateDiagram? {
        if case .success(let diagram) = result { return diagram }
        return nil
    }

    var analysisError: StateDiagramAnalysisError? {
        if case .failure(let error) = result { return error }
        return nil
    }

    // MARK: - Layout

    var layout: StateLayoutModel {
        StateLayoutModel(diagram: diagram ?? StateDiagram(), positionOverrides: positionOverrides)
    }

    // MARK: - LayoutBackedCanvas

    var allNodeIDs: [String] { layout.nodes.map(\.id) }

    func nodeFrame(_ id: String) -> CGRect? { layout.frame(for: id) }

    var defaultNodeSize: CGSize { CGSize(width: 80, height: 40) }

    // MARK: - Image Export

    func exportPNGData(scale: CGFloat = 2) throws -> Data {
        guard let diagram else { throw DiagramImageRenderError.renderingFailed }
        return try StateImageRenderer().renderPNG(
            stateDiagram: diagram,
            positionOverrides: positionOverrides,
            context: RenderingContext(scale: scale)
        )
    }
}
