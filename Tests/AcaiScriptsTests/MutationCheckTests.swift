import Foundation
import Testing

@Test func mutationCheckClassifiesSurvivingCaughtAndUncompilableHunks() throws {
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
    let log = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    #expect(process.terminationStatus == 0, "\(String(decoding: log, as: UTF8.self))")
}
