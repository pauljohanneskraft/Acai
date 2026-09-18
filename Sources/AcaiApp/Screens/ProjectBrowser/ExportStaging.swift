import Foundation

/// An export written to disk so the share sheet can hand it on as a file under its own name.
struct StagedExport: Sendable {
    let id: UUID
    let fileURL: URL
}

/// Stages each export in its own folder beneath `root`, so the shared file keeps its user-visible
/// name without colliding with an earlier export of the same name.
struct ExportStaging: Sendable {
    let root: URL

    static let standard = ExportStaging(
        root: FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
    )

    func stage(_ data: Data, as filename: String) throws -> StagedExport {
        let id = UUID()
        let folder = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safeName = filename.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let fileURL = try PathEscapeGuard(root: folder).resolvedURL(forRelativePath: safeName)
        try data.write(to: fileURL, options: .atomic)
        return StagedExport(id: id, fileURL: fileURL)
    }

    func discardAll() {
        try? FileManager.default.removeItem(at: root)
    }
}
