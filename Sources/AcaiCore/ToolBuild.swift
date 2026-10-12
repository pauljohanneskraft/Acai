import Foundation

/// The build of the running tool. Parser output can change between builds that share a
/// `toolVersion`, so the executable's own `(modified, size)` tells them apart.
struct ToolBuild: Codable, Equatable, Sendable {
    static let current = ToolBuild(
        toolVersion: AcaiConstants.standard.toolVersion, executable: Bundle.main.executableURL
    )

    let toolVersion: String
    let executableModified: Date?
    let executableSize: Int?

    init(toolVersion: String, executable: URL?) {
        let attributes = executable.flatMap {
            try? FileManager.default.attributesOfItem(atPath: $0.resolvingSymlinksInPath().path)
        }
        self.toolVersion = toolVersion
        self.executableModified = attributes?[.modificationDate] as? Date
        self.executableSize = (attributes?[.size] as? NSNumber)?.intValue
    }
}
