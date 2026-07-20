import Foundation
import SwiftGitX

/// Resolves a revision string — `HEAD`, `HEAD~N`/`HEAD^` chains, a branch or tag name, or a full
/// 40-character commit SHA — to a commit in a repository.
///
/// `SwiftGitX` doesn't expose libgit2's general `git_revparse_single` (the C API backing `git
/// rev-parse`'s full grammar — ranges, `@{upstream}`, etc.), only typed lookups (`repository.show`,
/// `repository.branch`, `repository.tag`). This covers the subset Acai's own ref picker
/// (`GitRefs`/`DeltaComparisonBar`) and default "HEAD" actually produce, not arbitrary revspecs.
struct GitReference {
    let name: String

    enum Failure: LocalizedError {
        case notFound(String)

        var errorDescription: String? {
            switch self {
            case .notFound(let name):
                "Couldn't find \"\(name)\" as a branch, tag, commit, or HEAD in this repository."
            }
        }
    }

    /// Resolves `name` to a commit in `repository`.
    func resolve(in repository: Repository) throws -> Commit {
        let (base, parentSteps) = splitParentSuffix(from: name)
        let commit = try resolveBase(base, in: repository)
        return try walkParents(from: commit, steps: parentSteps)
    }

    /// Splits a trailing `~N`/`^` chain off a revision string, e.g. `"HEAD~3"` -> (`"HEAD"`, 3),
    /// `"main^^"` -> (`"main"`, 2). A revision with no such suffix returns `(name, 0)`.
    private func splitParentSuffix(from name: String) -> (base: String, steps: Int) {
        var remaining = Substring(name)
        var steps = 0

        while let last = remaining.last {
            if last == "^" {
                remaining.removeLast()
                steps += 1
            } else if last == "~" || last.isNumber {
                guard let tildeIndex = remaining.lastIndex(of: "~") else { break }
                let digits = remaining[remaining.index(after: tildeIndex)...]
                guard !digits.isEmpty, let count = Int(digits) else { break }
                remaining = remaining[..<tildeIndex]
                steps += count
            } else {
                break
            }
        }

        return (String(remaining), steps)
    }

    private func resolveBase(_ base: String, in repository: Repository) throws -> Commit {
        if base.isEmpty || base == "HEAD" {
            guard let commit = try repository.HEAD.target as? Commit else {
                throw Failure.notFound(name)
            }
            return commit
        }

        if let remoteBranch = repository.branch["origin/\(base)", type: .remote],
            let commit = remoteBranch.target as? Commit {
            return commit
        }

        if let localBranch = repository.branch[base, type: .local],
            let commit = localBranch.target as? Commit {
            return commit
        }

        if let tag = repository.tag[base], let commit = tag.target as? Commit {
            return commit
        }

        if base.count == 40, let oid = try? OID(hex: base), let commit: Commit = try? repository.show(id: oid) {
            return commit
        }

        throw Failure.notFound(name)
    }

    private func walkParents(from commit: Commit, steps: Int) throws -> Commit {
        var current = commit
        for _ in 0..<steps {
            guard let parent = try current.parents.first else {
                throw Failure.notFound(name)
            }
            current = parent
        }
        return current
    }
}
