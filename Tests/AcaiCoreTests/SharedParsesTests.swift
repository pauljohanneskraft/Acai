import Foundation
import Testing
import AcaiCore
import AcaiTestSupport

private struct CountingParser: CodeParser {
    var language: CodeArtifact.SourceLanguage { .init(rawValue: "fixture") }
    var fileExtensions: [String] { ["fx"] }
    var configuration: LanguageConfiguration { LanguageConfiguration() }
    let parsedFiles: Locked<[String]>

    func parse(source: String, fileName: String) -> CodeArtifact {
        parsedFiles.withValue { $0.append(fileName) }
        let name = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let type = TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: .class, accessLevel: .public,
            location: .init(filePath: fileName, line: 1, column: 1)
        )
        return CodeArtifact(metadata: .init(sourceLanguage: language, filePaths: [fileName]), types: [type])
    }
}

@Suite("Parses shared between analyses")
struct SharedParsesTests {
    private static let fileCount = 8

    private func tree(changingLastFileTo changed: String? = nil) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AcaiSharedParsesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for index in 0..<Self.fileCount {
            let isLast = index == Self.fileCount - 1
            let contents = isLast ? changed ?? "Type\(index)" : "Type\(index)"
            try contents.write(to: root.appendingPathComponent("File\(index).fx"), atomically: true, encoding: .utf8)
        }
        return root
    }

    @Test("Two analyses run side by side parse a file they hold unchanged once, and report what unshared ones do")
    func unchangedFilesAreParsedOnceAcrossBothAnalyses() async throws {
        let old = try tree()
        let new = try tree(changingLastFileTo: "Renamed")
        defer {
            try? FileManager.default.removeItem(at: old)
            try? FileManager.default.removeItem(at: new)
        }
        let parsedFiles = Locked<[String]>([])
        let service = AnalysisService(parsers: [CountingParser(parsedFiles: parsedFiles)])

        let parses = SharedParses()
        async let sharedOld = service.sharing(parses).analyzeProject(at: old, allowedLanguages: [])
        async let sharedNew = service.sharing(parses).analyzeProject(at: new, allowedLanguages: [])
        let shared = try await (old: sharedOld, new: sharedNew)

        #expect(parsedFiles.value.count == Self.fileCount + 1)
        #expect(parsedFiles.value.filter { $0 == "File\(Self.fileCount - 1).fx" }.count == 2)

        #expect(try await shared.old == service.analyzeProject(at: old, allowedLanguages: []))
        #expect(try await shared.new == service.analyzeProject(at: new, allowedLanguages: []))
    }

    @Test("A service not given shared parses parses every file of every analysis")
    func unsharedAnalysesEachParseEveryFile() async throws {
        let root = try tree()
        defer { try? FileManager.default.removeItem(at: root) }
        let parsedFiles = Locked<[String]>([])
        let service = AnalysisService(parsers: [CountingParser(parsedFiles: parsedFiles)])

        _ = try await service.analyzeProject(at: root, allowedLanguages: [])
        _ = try await service.analyzeProject(at: root, allowedLanguages: [])

        #expect(parsedFiles.value.count == Self.fileCount * 2)
    }
}
