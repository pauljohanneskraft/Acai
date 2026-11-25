import Foundation
import Testing

@Suite("mutation_check.sh", .timeLimit(.minutes(10)))
struct MutationCheckTests {

    @Test func everyHunkOutcomeIsClassified() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [repositoryRoot.appendingPathComponent("Scripts/mutation_check_test.sh").path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        try process.run()
        let log = String(bytes: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()

        #expect(process.terminationStatus == 0, "\(log)")
    }
}
