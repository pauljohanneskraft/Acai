import Foundation
import SwiftUI
import UMLLibrary
import UMLCore
import UMLDiagram
import UniformTypeIdentifiers

// MARK: - DOT Export & Freeform Diagram Conversion

extension ProjectBrowserViewModel {

    // MARK: DOT Export

    func generateDOT(for codebaseID: UUID) -> String {
        guard let codebase = codebase(for: codebaseID) else { return "digraph UML { }" }
        let url = URL(fileURLWithPath: codebase.directoryPath).standardizedFileURL
        let options = ClassDiagramOptions(theme: DiagramThemeSelection.currentExportTheme)

        if var artifact = artifact(for: codebaseID) {
            if artifact.metadata.sourceLanguage == .dart {
                artifact = artifact.filteringGeneratedDartTypes()
            }
            return DOTGenerator(options: options).generate(from: artifact)
        }

        if var artifact = try? AnalysisService.shared.analyzeProject(at: url, allowedLanguages: []) {
            if artifact.metadata.sourceLanguage == .dart {
                artifact = artifact.filteringGeneratedDartTypes()
            }
            return DOTGenerator(options: options).generate(from: artifact)
        }

        return "digraph UML { label=\"No analysis available\" }"
    }

    func exportDOT(for codebaseID: UUID) {
        let dot = generateDOT(for: codebaseID)
        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.plainText]
        panel.nameFieldStringValue = "\(codebase(for: codebaseID)?.name ?? "diagram").txt"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try dot.data(using: .utf8)?.write(to: url, options: .atomic)
            } catch {
                print("Export failed: \(error)")
            }
        }
        #endif
    }

    // MARK: Mermaid Export

    /// Renders the codebase's class diagram as Mermaid (embeds directly in Markdown).
    func generateMermaid(for codebaseID: UUID) -> String {
        guard let codebase = codebase(for: codebaseID) else { return "classDiagram\n" }
        let url = URL(fileURLWithPath: codebase.directoryPath).standardizedFileURL
        let options = ClassDiagramOptions(theme: DiagramThemeSelection.currentExportTheme)

        if var artifact = artifact(for: codebaseID) {
            if artifact.metadata.sourceLanguage == .dart {
                artifact = artifact.filteringGeneratedDartTypes()
            }
            return ClassDiagramMermaidRenderer(options: options).generate(from: artifact)
        }

        if var artifact = try? AnalysisService.shared.analyzeProject(at: url, allowedLanguages: []) {
            if artifact.metadata.sourceLanguage == .dart {
                artifact = artifact.filteringGeneratedDartTypes()
            }
            return ClassDiagramMermaidRenderer(options: options).generate(from: artifact)
        }

        return "classDiagram\n"
    }

    func exportMermaid(for codebaseID: UUID) {
        let mermaid = generateMermaid(for: codebaseID)
        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.plainText]
        panel.nameFieldStringValue = "\(codebase(for: codebaseID)?.name ?? "diagram").mmd"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try mermaid.data(using: .utf8)?.write(to: url, options: .atomic)
            } catch {
                print("Export failed: \(error)")
            }
        }
        #endif
    }

    // MARK: Save as Freeform Diagram

    /// Convert a stored diagram to a freeform diagram.
    func saveAsFreeformDiagram(
        id diagramId: UUID,
        positions: [String: CGPoint],
        scale: CGFloat,
        offset: CGPoint
    ) {
        guard let diagram = generatedDiagram(for: diagramId),
              let pIdx = store.projects.firstIndex(where: { $0.generatedDiagramIDs.contains(diagramId) }),
              var artifact = store.artifact(for: diagram.codebaseID)?.resolvingExtensions() else { return }

        // Sequence diagrams have no class configuration; default to hiding generated Dart types.
        let hideGeneratedDartTypes = diagram.classConfiguration?.hideGeneratedDartTypes ?? true
        if hideGeneratedDartTypes && artifact.metadata.sourceLanguage == .dart {
            artifact = artifact.filteringGeneratedDartTypes()
        }
        let freeformDiagram = diagram.convertToFreeform(
            artifact: artifact,
            positions: positions,
            scale: scale,
            offset: offset
        )
        store.projects[pIdx].freeformDiagramIDs.append(freeformDiagram.id)
        store.saveFreeformDiagram(freeformDiagram)
        persistChanges()
        selection = .freeformDiagram(freeformDiagram.id)
    }
}
