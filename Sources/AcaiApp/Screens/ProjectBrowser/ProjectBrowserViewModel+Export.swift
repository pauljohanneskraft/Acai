import Foundation
import SwiftUI
import AcaiLibrary
import AcaiCore
import AcaiDiagram
import UniformTypeIdentifiers

/// A diagram view model that can render its current diagram to PNG data.
@MainActor
protocol DiagramImageExporting {
    func exportPNGData(scale: CGFloat) throws -> Data
}

/// A rendered export waiting to be written to a user-chosen location — the payload behind the
/// single `.fileExporter` modifier in `ProjectBrowserView`, shared by image/DOT/Mermaid export.
struct PendingExport: Identifiable {
    let id = UUID()
    let filename: String
    let contentType: UTType
    let data: Data
}

/// A `FileDocument` wrapping raw bytes, so `PendingExport`'s PNG/DOT/Mermaid payloads can all drive
/// the same `.fileExporter` call regardless of content type.
struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - DOT Export & Freeform Diagram Conversion

extension ProjectBrowserViewModel {

    /// Renders the exporter's PNG and queues it for `.fileExporter`, routing any failure to the
    /// error alert. Shared by every generated-diagram view so the render/error handling lives in
    /// one place.
    func exportImage(named name: String, using exporter: any DiagramImageExporting) {
        do {
            let data = try exporter.exportPNGData(scale: 2)
            pendingExport = PendingExport(filename: "\(name).png", contentType: .png, data: data)
        } catch {
            store.report("Image export failed: \(error.localizedDescription)")
        }
    }

    // MARK: DOT Export

    func generateDOT(for codebaseID: UUID) -> String {
        guard let codebase = codebase(for: codebaseID) else { return "digraph Acai { }" }

        if let artifact = artifact(for: codebaseID) {
            return ClassDiagramDOTRenderer(options: exportOptions(for: artifact))
                .generate(from: hidingGeneratedTypes(artifact))
        }

        do {
            let access = ScopedResourceAccess(path: codebase.directoryPath, bookmark: codebase.securityScopedBookmark)
            return try access.withResolvedURL { url in
                let artifact = try AnalysisService.standard.analyzeProject(at: url, allowedLanguages: [])
                return ClassDiagramDOTRenderer(options: exportOptions(for: artifact))
                    .generate(from: hidingGeneratedTypes(artifact))
            }
        } catch {
            store.report("Could not analyze project for DOT export: \(error.localizedDescription)")
            return "digraph Acai { label=\"No analysis available\" }"
        }
    }

    /// Export options carrying the current theme and the artifact's resolved language quirks.
    private func exportOptions(for artifact: CodeArtifact) -> ClassDiagramOptions {
        ClassDiagramOptions(
            theme: DiagramThemeSelection.currentExportTheme,
            languages: artifact.standardLanguageResolver
        )
    }

    /// Drops the source language's machine-generated types when it declares a generated-code filter.
    private func hidingGeneratedTypes(_ artifact: CodeArtifact) -> CodeArtifact {
        artifact.filteringGeneratedTypes(using: artifact.standardLanguageResolver)
    }

    func exportDOT(for codebaseID: UUID) {
        let dot = generateDOT(for: codebaseID)
        let name = codebase(for: codebaseID)?.name ?? "diagram"
        pendingExport = PendingExport(filename: "\(name).txt", contentType: .plainText, data: Data(dot.utf8))
    }

    // MARK: Mermaid Export

    /// Renders the codebase's class diagram as Mermaid (embeds directly in Markdown).
    func generateMermaid(for codebaseID: UUID) -> String {
        guard let codebase = codebase(for: codebaseID) else { return "classDiagram\n" }

        if let artifact = artifact(for: codebaseID) {
            return ClassDiagramMermaidRenderer(options: exportOptions(for: artifact))
                .generate(from: hidingGeneratedTypes(artifact))
        }

        do {
            let access = ScopedResourceAccess(path: codebase.directoryPath, bookmark: codebase.securityScopedBookmark)
            return try access.withResolvedURL { url in
                let artifact = try AnalysisService.standard.analyzeProject(at: url, allowedLanguages: [])
                return ClassDiagramMermaidRenderer(options: exportOptions(for: artifact))
                    .generate(from: hidingGeneratedTypes(artifact))
            }
        } catch {
            store.report("Could not analyze project for Mermaid export: \(error.localizedDescription)")
            return "classDiagram\n"
        }
    }

    func exportMermaid(for codebaseID: UUID) {
        let mermaid = generateMermaid(for: codebaseID)
        let name = codebase(for: codebaseID)?.name ?? "diagram"
        pendingExport = PendingExport(filename: "\(name).mmd", contentType: .plainText, data: Data(mermaid.utf8))
    }

    // MARK: Codebase Atlas Export

    /// Bundles every diagram, statistic, and finding for `codebaseID` into one paginated PDF
    /// (``CodebaseAtlasBuilder``) and queues it for `.fileExporter`. Routed through
    /// `store.activityCenter.run` (same as `reindex`) so it shows up as the codebase row's spinner.
    func exportAtlas(for codebaseID: UUID) async {
        guard let codebase = codebase(for: codebaseID) else { return }
        guard let artifact = artifact(for: codebaseID) else {
            store.report("Could not export Atlas: \"\(codebase.name)\" hasn't been indexed yet.")
            return
        }
        await ensureAnalysisLoaded(codebaseID: codebaseID)
        guard let analysis = analysis(for: codebaseID) else {
            store.report("Could not export Atlas: analysis for \"\(codebase.name)\" isn't ready yet.")
            return
        }
        guard let projectID = projectID(for: codebaseID),
              let project = store.projects.first(where: { $0.id == projectID })
        else { return }

        let diagrams = generatedDiagramsForProject(projectID).filter { $0.codebaseID == codebaseID }
        let findings = FindingsAggregator(project: project, model: self).findings(for: codebase)
        let builder = CodebaseAtlasBuilder(
            codebase: codebase, artifact: artifact, diagrams: diagrams,
            metrics: analysis.metrics, findings: findings)

        do {
            let data = try await store.activityCenter.run(
                title: "Exporting \(codebase.name) atlas…", kind: .other(systemImage: "doc.richtext"),
                subject: .codebase(codebaseID)
            ) {
                try await builder.build()
            }
            // Cancelled before finishing: don't queue a result we discarded.
            guard let data else { return }
            pendingExport = PendingExport(filename: "\(codebase.name).pdf", contentType: .pdf, data: data)
        } catch {
            store.report("Atlas export failed: \(error.localizedDescription)")
        }
    }

    // MARK: Save as Freeform Diagram

    /// Convert a stored diagram to a freeform diagram.
    ///
    /// - Parameter includeMetricsNote: the opt-in — Package/Call Graph screens thread the user's
    ///   checkbox choice through here; every other diagram type calls this with the default `false`
    ///   since they have no comparable metric to carry over.
    func saveAsFreeformDiagram(
        id diagramId: UUID,
        positions: [String: CGPoint],
        scale: CGFloat,
        offset: CGPoint,
        includeMetricsNote: Bool = false
    ) {
        guard let diagram = generatedDiagram(for: diagramId),
              let pIdx = store.projects.firstIndex(where: { $0.generatedDiagramIDs.contains(diagramId) }),
              let semantic = store.artifact(for: diagram.codebaseID) else { return }

        // Flatten to the same node ids the diagram was rendered with — the `positions` dict is keyed
        // by them. Generated-type filtering stays conditional on the diagram's own configuration.
        var artifact = CodebaseAnalyzer().flattenedForDisplay(semantic)

        // Sequence diagrams have no class configuration; default to hiding generated types.
        let hideGeneratedTypes = diagram.classConfiguration?.hideGeneratedTypes ?? true
        if hideGeneratedTypes {
            artifact = artifact.filteringGeneratedTypes(using: artifact.standardLanguageResolver)
        }
        let freeformDiagram = diagram.convertToFreeform(
            artifact: artifact,
            positions: positions,
            scale: scale,
            offset: offset,
            includeMetricsNote: includeMetricsNote
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
