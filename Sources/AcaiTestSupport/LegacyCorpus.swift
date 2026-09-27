import Foundation

/// A committed corpus of JSON written by an earlier build's encoder, so a `Codable` model change
/// that stops decoding already-persisted data fails in the test suite rather than in an install.
///
/// Each snapshot is a directory named by the label it was recorded under, holding whatever file
/// layout its owning store uses. Covering a format change means recording a *new* snapshot; an
/// existing one is never rewritten, since an old snapshot is the only evidence that yesterday's
/// file still decodes.
public struct LegacyCorpus {
    public let root: URL

    /// `testFile` defaults to the calling test file, so the corpus sits next to the tests that
    /// read it — located by path rather than `Bundle.module`, which would need the JSON declared
    /// as a resource in every target.
    public init(directoryName: String = "__LegacyCorpus__", testFile: StaticString = #filePath) {
        root = URL(fileURLWithPath: "\(testFile)")
            .deletingLastPathComponent()
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    /// Every committed snapshot, oldest label first.
    public var snapshots: [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? []
        return contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// The label a recording run writes under: `ACAI_LEGACY_CORPUS_LABEL`, else today's date.
    /// `nil` unless `ACAI_RECORD_LEGACY_CORPUS=1`, which is the only way a snapshot is ever created.
    public var recordingLabel: String? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["ACAI_RECORD_LEGACY_CORPUS"] == "1" else { return nil }
        if let label = environment["ACAI_LEGACY_CORPUS_LABEL"], !label.isEmpty { return label }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    /// The empty directory a recording run fills, or `nil` when that label is already committed —
    /// recording never overwrites a snapshot.
    public func makeSnapshotDirectory(label: String) throws -> URL? {
        let directory = root.appendingPathComponent(label, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: directory.path) else { return nil }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
