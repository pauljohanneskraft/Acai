import Foundation
import AcaiCore

/// Decodes a pre-baked `CodeArtifact` instead of parsing `url`'s contents — `url`/`fileFilter` are
/// ignored.
struct FixtureCodebaseAnalyzer: CodebaseAnalyzing {
    let artifactURL: URL

    enum Failure: LocalizedError {
        case couldNotDecode(URL, underlying: Error)

        var errorDescription: String? {
            switch self {
            case .couldNotDecode(let url, let underlying):
                "Could not decode fixture artifact at \(url.path): \(underlying.localizedDescription)"
            }
        }
    }

    func enrichedArtifact(at url: URL, fileFilter: FileFilter?) throws -> CodeArtifact {
        do {
            return try JSONDecoder().decode(CodeArtifact.self, from: Data(contentsOf: artifactURL))
        } catch {
            throw Failure.couldNotDecode(artifactURL, underlying: error)
        }
    }
}
