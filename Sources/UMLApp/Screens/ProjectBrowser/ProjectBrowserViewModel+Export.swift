import Foundation
import SwiftUI
import UMLLibrary
import UMLCore
import UMLDiagram
import UniformTypeIdentifiers

// MARK: - DOT Export & Custom Diagram Conversion

extension ProjectBrowserViewModel {

    // MARK: DOT Export

    func generateDOT(for codebaseID: UUID) -> String {
        guard let codebase = codebase(for: codebaseID) else { return "digraph UML { }" }
        let url = URL(fileURLWithPath: codebase.directoryPath).standardizedFileURL

        if var artifact = artifact(for: codebaseID) {
            if artifact.metadata.sourceLanguage == .dart {
                artifact = artifact.filteringGeneratedDartTypes()
            }
            return DOTGenerator().generate(from: artifact)
        }

        if var artifact = try? AnalysisService.shared.analyzeProject(at: url, allowedLanguages: []) {
            if artifact.metadata.sourceLanguage == .dart {
                artifact = artifact.filteringGeneratedDartTypes()
            }
            return DOTGenerator().generate(from: artifact)
        }

        return "digraph UML { label=\"No analysis available\" }"
    }

    func exportDOT(for codebaseID: UUID) {
        let dot = generateDOT(for: codebaseID)
        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(importedAs: "org.graphviz.dot", conformingTo: .text)]
        panel.nameFieldStringValue = "\(codebase(for: codebaseID)?.name ?? "diagram").dot"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try dot.data(using: .utf8)?.write(to: url, options: .atomic)
            } catch {
                print("Export failed: \(error)")
            }
        }
        #endif
    }

    // MARK: Save as Custom Diagram

    /// Convert a stored diagram to a custom diagram.
    func saveAsCustomDiagram(
        id diagramId: UUID,
        positions: [String: CGPoint],
        scale: CGFloat,
        offset: CGPoint
    ) {
        guard let diagram = generatedDiagram(for: diagramId),
              let pIdx = store.projects.firstIndex(where: { $0.generatedDiagramIDs.contains(diagramId) }),
              let artifact = artifact(for: diagram.codebaseID) else { return }

        var resolved = artifact.resolvingExtensions()
        if diagram.configuration.hideGeneratedDartTypes && artifact.metadata.sourceLanguage == .dart {
            resolved = resolved.filteringGeneratedDartTypes()
        }
        let customDiagram = diagram.convertToCustom(
            artifact: artifact,
            positions: positions,
            scale: scale,
            offset: offset
        )
        store.projects[pIdx].customDiagramIDs.append(customDiagram.id)
        store.saveCustomDiagram(customDiagram)
        persistChanges()
        selection = .customDiagram(customDiagram.id)
    }
}
