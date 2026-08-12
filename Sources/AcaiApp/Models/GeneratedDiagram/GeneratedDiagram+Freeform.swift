import Foundation
import AcaiCore
import AcaiDiagram
import AcaiLibrary
import AcaiRender

/// "Save as Freeform" for every diagram type. Each of the five diagram contents converts through
/// its own `FreeformConversion` conformer — see that protocol's doc comment for what's shared (the
/// outer skeleton, id-map bookkeeping, position-fallback tiering) versus what deliberately stays
/// per-type (node/edge content construction, Class's grouping boxes, the metrics footer).
extension GeneratedDiagram {

    /// - Parameter includeMetricsNote: When true, Package/Call Graph conversions append one
    ///   read-only `.note` node summarizing the coupling/coverage figures already computed for the
    ///   *current, non-diff* artifact (a diagram with `comparisonGitRef` set still converts against
    ///   the plain current-tree view — the note doesn't reflect the diff). Ignored by Class/Sequence/
    ///   State, which have no comparable metric to carry over.
    func convertToFreeform(
        artifact: CodeArtifact,
        positions: [String: CGPoint],
        scale: CGFloat,
        offset: CGPoint,
        includeMetricsNote: Bool = false
    ) -> FreeformDiagram {
        let context = FreeformConversionContext(
            diagram: self, artifact: artifact, positions: positions, scale: scale, offset: offset
        )
        // Module Coupling, Hotspot, and Cycle Diagram are read-only analysis views — a scatter/
        // chart point or an isolated cycle member has no sensible "freeform node"
        // equivalent the way a class/module/participant does, so there's deliberately no conformer
        // for them. Handled explicitly (not left to fall through to the `ClassFreeformConversion`
        // default below, which would silently misinterpret their artifact as a class diagram):
        // "Save as Freeform" isn't offered on any of these three types' toolbars, so this path is
        // unreachable from the UI today — an empty diagram if it's ever invoked directly.
        if [DiagramType.moduleCoupling, .hotspot, .cycleDiagram].contains(content.type) {
            return FreeformDiagram(
                name: name + " (Freeform)", canvasScale: scale, canvasOffsetX: offset.x, canvasOffsetY: offset.y
            )
        }
        if case .sequenceDiagram(let config) = content {
            return SequenceFreeformConversion(context: context, configuration: config).makeFreeformDiagram()
        }
        if case .stateDiagram(let config) = content, let config {
            return StateFreeformConversion(context: context, configuration: config).makeFreeformDiagram()
        }
        if case .packageDiagram = content {
            return PackageFreeformConversion(
                context: context, includeMetricsNote: includeMetricsNote
            ).makeFreeformDiagram()
        }
        if case .callGraph(let scope) = content {
            return CallGraphFreeformConversion(
                context: context, scope: scope, includeMetricsNote: includeMetricsNote
            ).makeFreeformDiagram()
        }
        return ClassFreeformConversion(context: context).makeFreeformDiagram()
    }
}
