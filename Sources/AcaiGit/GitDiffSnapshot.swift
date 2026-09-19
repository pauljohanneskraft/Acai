import Foundation
import SwiftGitX

/// Produces a codebase's tree as it was at a git revision, in a fresh temporary directory.
/// **Read-only**: the working tree, index, and HEAD of the repository `directory` belongs to are
/// never touched. `directory` may be the repository root or any subdirectory of it — only that
/// subtree is extracted. Caller is responsible for removing the returned directory afterward.
public struct GitDiffSnapshot {
    public let directory: URL
    public let reference: String

    public init(directory: URL, reference: String) {
        self.directory = directory
        self.reference = reference
    }

    public enum Failure: LocalizedError {
        case notAGitRepository(String)
        case subpathNotFound(String, String)
        case fileNotFound(String, String)

        public var errorDescription: String? {
            switch self {
            case .notAGitRepository(let path):
                "\"\(path)\" is not inside a git repository."
            case .subpathNotFound(let path, let reference), .fileNotFound(let path, let reference):
                "\"\(path)\" didn't exist at revision \"\(reference)\"."
            }
        }
    }

    /// The commit `reference` names, e.g. to fingerprint an analysis made at that revision.
    public func commitSHA() throws -> String {
        let (_, commit) = try resolvedCommit()
        return commit.id.hex
    }

    /// One file of the subtree as it was at `reference`, written to a fresh temporary directory
    /// under its own name. `relativePath` is relative to `directory` and may not climb out of it.
    public func extractedFile(relativePath: String) throws -> URL {
        let components = relativePath.split(separator: "/").map(String.init)
        guard let fileName = components.last, !components.contains("..") else {
            throw Failure.fileNotFound(relativePath, reference)
        }
        let (repository, commit) = try resolvedCommit()
        do {
            var tree = try subtree(of: commit, in: repository)
            for component in components.dropLast() {
                guard let entry = tree.entries.first(where: { $0.name == component && $0.type == .tree }) else {
                    throw Failure.fileNotFound(relativePath, reference)
                }
                tree = try repository.show(id: entry.id)
            }
            guard let entry = tree.entries.first(where: { $0.name == fileName && $0.type == .blob }) else {
                throw Failure.fileNotFound(relativePath, reference)
            }
            let blob: Blob = try repository.show(id: entry.id)
            let destination = try FileManager.default.url(
                for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: directory, create: true)
            let fileURL = destination.appendingPathComponent(fileName)
            try blob.content.write(to: fileURL)
            return fileURL
        } catch let error as SwiftGitXError {
            throw error.asFailure("Couldn't read \"\(relativePath)\" at \"\(reference)\"")
        }
    }

    private func resolvedCommit() throws -> (Repository, Commit) {
        guard let root = GitRepositoryRoot(directory: directory).find() else {
            throw Failure.notAGitRepository(directory.path)
        }
        let repository: Repository
        do {
            repository = try Repository(at: root, createIfNotExists: false)
        } catch {
            throw Failure.notAGitRepository(directory.path)
        }
        do {
            return (repository, try GitReference(name: reference).resolve(in: repository))
        } catch let error as SwiftGitXError {
            throw error.asFailure("Couldn't resolve \"\(reference)\"")
        }
    }

    public func extractedDirectory() throws -> URL {
        let (repository, commit) = try resolvedCommit()

        let destination = try FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: directory, create: true)

        do {
            let tree = try subtree(of: commit, in: repository)
            try write(tree: tree, to: destination, repository: repository)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            if error is CancellationError { throw error }
            if let error = error as? SwiftGitXError {
                throw error.asFailure("Couldn't extract \"\(reference)\"")
            }
            throw error
        }

        return destination
    }

    private func subtree(of commit: Commit, in repository: Repository) throws -> Tree {
        let root = try commit.tree
        let standardizedDirectory = directory.standardizedFileURL.path
        let standardizedWorkingDirectory = try repository.workingDirectory.standardizedFileURL.path

        guard standardizedDirectory != standardizedWorkingDirectory else { return root }
        guard standardizedDirectory.hasPrefix(standardizedWorkingDirectory + "/") else {
            throw Failure.notAGitRepository(directory.path)
        }

        let relativePath = String(standardizedDirectory.dropFirst(standardizedWorkingDirectory.count + 1))
        var tree = root
        for component in relativePath.split(separator: "/") {
            guard let entry = tree.entries.first(where: { $0.name == component && $0.type == .tree }) else {
                throw Failure.subpathNotFound(relativePath, reference)
            }
            tree = try repository.show(id: entry.id)
        }
        return tree
    }

    private func write(tree: Tree, to directory: URL, repository: Repository) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for entry in tree.entries {
            try Task.checkCancellation()
            let entryURL = directory.appendingPathComponent(entry.name)
            switch entry.type {
            case .tree:
                let subtree: Tree = try repository.show(id: entry.id)
                try write(tree: subtree, to: entryURL, repository: repository)
            case .blob:
                let blob: Blob = try repository.show(id: entry.id)
                try blob.content.write(to: entryURL)
            default:
                continue
            }
        }
    }
}
