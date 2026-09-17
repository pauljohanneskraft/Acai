import Testing
import Foundation
import CoreGraphics
import SwiftUI
import AcaiPNGComparison
@testable import AcaiRender
@testable import AcaiCore
@testable import AcaiDiff

/// Compared perceptually, like every render snapshot: two renders of the same view under a loaded,
/// parallel test run are not bit-identical, so byte or exact-pixel equality fails intermittently.
/// `badgeOverrideChangesTheRenderedPixels` proves the same comparison still sees a badge.
@Suite("Class diagram delta badge PNG export")
struct ClassDeltaBadgeExportTests {
    private let comparison = PNGGoldenComparison()

    private func laidOutSingleNode() -> LaidOutDiagram {
        let type = TypeDeclaration(
            id: "Widget", name: "Widget", qualifiedName: "Widget", kind: .class, accessLevel: .public,
            location: SourceLocation(filePath: "Sources/A/Widget.swift", line: 1, column: 1))
        let node = GeneratedDiagramNode(from: type)
        return LaidOutDiagram(
            nodes: [node], edges: [],
            positions: [node.id: CGPoint(x: 100, y: 100)],
            sizes: [node.id: CGSize(width: 160, height: 90)],
            groupingBoxes: [])
    }

    @Test @MainActor func badgeOverrideChangesTheRenderedPixels() throws {
        let laidOut = laidOutSingleNode()
        let colorsOnly = ClassColorOverrides(node: { _ in Color.orange }, badge: nil)
        let colorsAndBadge = ClassColorOverrides(node: { _ in Color.orange }, badge: { _ in .changed })

        let withoutBadge: Data
        let withBadge: Data
        do {
            withoutBadge = try ClassImageRenderer().renderPNG(laidOut: laidOut, colors: colorsOnly)
            withBadge = try ClassImageRenderer().renderPNG(laidOut: laidOut, colors: colorsAndBadge)
        } catch DiagramImageRenderError.renderingFailed, DiagramImageRenderError.encodingFailed {
            return
        }

        #expect(comparison.compare(committed: withoutBadge, rendered: withBadge) != .match)
    }

    @Test @MainActor func unchangedBadgeStatusRendersLikeNoBadge() throws {
        let laidOut = laidOutSingleNode()
        let noBadge = ClassColorOverrides(node: { _ in Color.orange }, badge: nil)
        let unchangedBadge = ClassColorOverrides(node: { _ in Color.orange }, badge: { _ in .unchanged })

        let withoutBadge: Data
        let withUnchangedBadge: Data
        do {
            withoutBadge = try ClassImageRenderer().renderPNG(laidOut: laidOut, colors: noBadge)
            withUnchangedBadge = try ClassImageRenderer().renderPNG(laidOut: laidOut, colors: unchangedBadge)
        } catch DiagramImageRenderError.renderingFailed, DiagramImageRenderError.encodingFailed {
            return
        }

        #expect(comparison.compare(committed: withoutBadge, rendered: withUnchangedBadge) == .match)
    }
}
