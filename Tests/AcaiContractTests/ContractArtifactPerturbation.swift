import Foundation
import AcaiCore
import AcaiLibrary

/// A way a parser could mishandle a variation, applied to the artifact the variation really produced.
protocol ContractArtifactPerturbation: Sendable, CustomStringConvertible {
    var name: String { get }
    /// `false` where the tolerance deliberately excuses this difference, so the check is not expected
    /// to catch it.
    func isCaught(under tolerance: ContractEquivalenceTolerance) -> Bool
    func perturbed(_ artifact: CodeArtifact) -> CodeArtifact
}

extension ContractArtifactPerturbation {
    var description: String { name }
    func isCaught(under tolerance: ContractEquivalenceTolerance) -> Bool { true }
}

/// What a variation that routed the file to no grammar at all looks like (#609).
struct ContractDroppedDeclarations: ContractArtifactPerturbation {
    let name = "every declaration dropped"

    func perturbed(_ artifact: CodeArtifact) -> CodeArtifact {
        var perturbed = artifact
        perturbed.types = []
        perturbed.freestandingFunctions = []
        perturbed.globalVariables = []
        perturbed.relationships = []
        return perturbed
    }
}

/// What a line ending left in the source looks like once it reaches a name.
struct ContractRenamedFirstDeclaration: ContractArtifactPerturbation {
    let name = "a stray character left on the first name"

    func perturbed(_ artifact: CodeArtifact) -> CodeArtifact {
        var perturbed = artifact
        if !perturbed.types.isEmpty {
            perturbed.types[0].name += "\u{0D}"
        } else if !perturbed.freestandingFunctions.isEmpty {
            perturbed.freestandingFunctions[0].name += "\u{0D}"
        } else if !perturbed.globalVariables.isEmpty {
            perturbed.globalVariables[0].name += "\u{0D}"
        }
        return perturbed
    }
}

/// What a location counted from the wrong line looks like.
struct ContractShiftedLines: ContractArtifactPerturbation {
    let name = "every location one line further down"

    func isCaught(under tolerance: ContractEquivalenceTolerance) -> Bool { !tolerance.ignoresLocations }

    func perturbed(_ artifact: CodeArtifact) -> CodeArtifact {
        ContractLocationShift(lines: 1, columns: 0).applied(to: artifact)
    }
}

/// What a column measured in UTF-8 bytes rather than characters looks like (#607).
struct ContractShiftedColumns: ContractArtifactPerturbation {
    let name = "every location one column further right"

    func isCaught(under tolerance: ContractEquivalenceTolerance) -> Bool { !tolerance.ignoresLocations }

    func perturbed(_ artifact: CodeArtifact) -> CodeArtifact {
        ContractLocationShift(lines: 0, columns: 1).applied(to: artifact)
    }
}

/// Moves every location in an artifact, so a perturbation does not have to know where they all are.
struct ContractLocationShift {
    let lines: Int
    let columns: Int

    func applied(to artifact: CodeArtifact) -> CodeArtifact {
        var shifted = artifact
        shifted.types = artifact.types.map { applied(to: $0) }
        shifted.freestandingFunctions = artifact.freestandingFunctions.map { applied(to: $0) }
        shifted.globalVariables = artifact.globalVariables.map { applied(to: $0) }
        return shifted
    }

    private func applied(to type: TypeDeclaration) -> TypeDeclaration {
        var shifted = type
        shifted.location = applied(to: type.location)
        shifted.members = type.members.map { applied(to: $0) }
        shifted.nestedTypes = type.nestedTypes.map { applied(to: $0) }
        shifted.enumCases = type.enumCases.map { enumCase in
            var shiftedCase = enumCase
            shiftedCase.location = applied(to: enumCase.location)
            return shiftedCase
        }
        return shifted
    }

    private func applied(to member: Member) -> Member {
        var shifted = member
        shifted.location = applied(to: member.location)
        shifted.callSites = member.callSites.map { callSite in
            var shiftedSite = callSite
            shiftedSite.location = applied(to: callSite.location)
            return shiftedSite
        }
        return shifted
    }

    private func applied(to location: SourceLocation?) -> SourceLocation? {
        guard var location else { return nil }
        location.line += lines
        location.column += columns
        location.endLine = location.endLine.map { $0 + lines }
        return location
    }
}
