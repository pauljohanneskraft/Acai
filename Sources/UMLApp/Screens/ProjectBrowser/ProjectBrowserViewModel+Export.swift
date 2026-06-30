import Foundation
import SwiftUI
import UMLLibrary
import UMLCore
import UMLDiagram
import UniformTypeIdentifiers

/// A diagram view model that can render its current diagram to PNG data.
@MainActor
protocol DiagramImageExporting {
    func exportPNGData(scale: CGFloat) throws -> Data
}

// MARK: - DOT Export & Freeform Diagram Conversion

extension ProjectBrowserViewModel {

    /// Presents a save panel and writes the exporter's PNG, routing any failure to the error alert.
    /// Shared by every generated-diagram view so the panel/write/error handling lives in one place.
    func exportImage(named name: String, using exporter: any DiagramImageExporting) {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(name).png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try exporter.exportPNGData(scale: 2).write(to: url, options: .atomic)
        } catch {
            store.report("Image export failed: \(error.localizedDescription)")
        }
        #endif
    }

    // MARK: DOT Export

    func generateDOT(for codebaseID: UUID) -> String {
        guard let codebase = codebase(for: codebaseID) else { return "digraph UML { }" }
        let url = URL(fileURLWithPath: codebase.directoryPath).standardizedFileURL

        if let artifact = artifact(for: codebaseID) {
            return ClassDiagramDOTRenderer(options: exportOptions(for: artifact))
                .generate(from: hidingGeneratedTypes(artifact))
        }

        do {
            let artifact = try AnalysisService.standard.analyzeProject(at: url, allowedLanguages: [])
            return ClassDiagramDOTRenderer(options: exportOptions(for: artifact))
                .generate(from: hidingGeneratedTypes(artifact))
        } catch {
            store.report("Could not analyze project for DOT export: \(error.localizedDescription)")
            return "digraph UML { label=\"No analysis available\" }"
        }
    }

    /// Export options carrying the current theme and the artifact's resolved language quirks.
    private func exportOptions(for artifact: CodeArtifact) -> ClassDiagramOptions {
        ClassDiagramOptions(
            theme: DiagramThemeSelection.currentExportTheme,
            language: artifact.standardLanguageConfiguration
        )
    }

    /// Drops the source language's machine-generated types when it declares a generated-code filter.
    private func hidingGeneratedTypes(_ artifact: CodeArtifact) -> CodeArtifact {
        guard let filter = artifact.standardLanguageConfiguration.generatedCodeFilter else { return artifact }
        return artifact.filteringGeneratedTypes(using: filter)
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
                store.report("Export failed: \(error.localizedDescription)")
            }
        }
        #endif
    }

    // MARK: Mermaid Export

    /// Renders the codebase's class diagram as Mermaid (embeds directly in Markdown).
    func generateMermaid(for codebaseID: UUID) -> String {
        guard let codebase = codebase(for: codebaseID) else { return "classDiagram\n" }
        let url = URL(fileURLWithPath: codebase.directoryPath).standardizedFileURL

        if let artifact = artifact(for: codebaseID) {
            return ClassDiagramMermaidRenderer(options: exportOptions(for: artifact))
                .generate(from: hidingGeneratedTypes(artifact))
        }

        do {
            let artifact = try AnalysisService.standard.analyzeProject(at: url, allowedLanguages: [])
            return ClassDiagramMermaidRenderer(options: exportOptions(for: artifact))
                .generate(from: hidingGeneratedTypes(artifact))
        } catch {
            store.report("Could not analyze project for Mermaid export: \(error.localizedDescription)")
            return "classDiagram\n"
        }
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
                store.report("Export failed: \(error.localizedDescription)")
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

        // Sequence diagrams have no class configuration; default to hiding generated types.
        let hideGeneratedTypes = diagram.classConfiguration?.hideGeneratedTypes ?? true
        if hideGeneratedTypes, let filter = artifact.standardLanguageConfiguration.generatedCodeFilter {
            artifact = artifact.filteringGeneratedTypes(using: filter)
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

// The generated-diagram view models all render their current diagram to PNG via the shared
// `DiagramImageRenderer`, so the export panel can drive any of them uniformly.
extension ClassDiagramViewModel: DiagramImageExporting {}
extension SequenceDiagramViewModel: DiagramImageExporting {}
extension StateDiagramViewModel: DiagramImageExporting {}
extension PackageDiagramViewModel: DiagramImageExporting {}
extension CallGraphViewModel: DiagramImageExporting {}
