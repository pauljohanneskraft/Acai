import Foundation

/// Parses shared by analyses run side by side, so a file they all see with identical contents is parsed once.
public final class SharedParses: @unchecked Sendable {
    private struct Key: Hashable {
        let language: CodeArtifact.SourceLanguage
        let fileName: String
        let source: String
    }

    private let lock = NSLock()
    private var parses: [Key: Task<CodeArtifact, Never>] = [:]

    public init() {}

    func artifact(parsing source: String, as fileName: String, with parser: any CodeParser) async -> CodeArtifact {
        let key = Key(language: parser.language, fileName: fileName, source: source)
        let parse = lock.withLock {
            if let inFlight = parses[key] { return inFlight }
            let parse = Task { await parser.parsedOnALargeStack(source: source, fileName: fileName) }
            parses[key] = parse
            return parse
        }
        return await parse.value
    }
}

extension AnalysisService {
    /// This service, parsing through `parses` — give the same instance to every analysis that should share.
    public func sharing(_ parses: SharedParses) -> AnalysisService {
        var service = self
        service.sharedParses = parses
        return service
    }
}
