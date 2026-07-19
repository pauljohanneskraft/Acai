import Foundation
import Testing
import ZipArchive
@testable import AcaiApp

/// SCRATCH — investigating whether SSZipArchive/minizip-ng sanitizes raw `../` entry paths for
/// regular (non-symlink) archive entries. Not meant to remain in the suite; deleted once the
/// question is answered.
@Suite("Zip slip scratch investigation")
struct ZipSlipScratchTest {
    @Test func rawTraversalEntryDoesItEscapeExtractedRoot() throws {
        let scratchDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-zipslip-scratch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratchDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratchDir) }

        let markerOutsideEverything = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-zipslip-marker.txt")
        try? FileManager.default.removeItem(at: markerOutsideEverything)

        let zipURL = URL(fileURLWithPath: "/private/tmp/claude-501/-Users-pauljohanneskraft-su-Developer-Acai/db956dc9-f967-42c0-8210-913c2cf1e668/scratchpad/zipslip.zip")
        let extractedRoot = scratchDir.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extractedRoot, withIntermediateDirectories: true)

        var extractionError: NSError?
        let succeeded = SSZipArchive.unzipFile(
            atPath: zipURL.path,
            toDestination: extractedRoot.path,
            preserveAttributes: false,
            overwrite: true,
            symlinksValidWithin: extractedRoot.path,
            nestedZipLevel: 0,
            password: nil,
            error: &extractionError,
            delegate: nil,
            progressHandler: nil,
            completionHandler: nil
        )

        print("succeeded:", succeeded)
        print("extractionError:", extractionError?.localizedDescription ?? "none")
        print("marker escaped to /tmp:", FileManager.default.fileExists(atPath: markerOutsideEverything.path))

        func dump(_ url: URL, indent: String = "") {
            guard let entries = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else {
                return
            }
            for entry in entries {
                print("\(indent)\(entry.lastPathComponent)")
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: entry.path, isDirectory: &isDir), isDir.boolValue {
                    dump(entry, indent: indent + "  ")
                }
            }
        }
        print("--- extractedRoot contents ---")
        dump(extractedRoot)
        print("--- scratchDir contents ---")
        dump(scratchDir)
    }
}
