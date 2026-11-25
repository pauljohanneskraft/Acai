import AcaiCore

/// Every declaration an artifact carries, keyed by simple name to the lines it was declared on.
struct DeclarationIndex: Sendable {
    private var linesByName: [String: Set<Int>] = [:]

    init(artifact: CodeArtifact) {
        for type in artifact.types {
            add(type)
        }
        for function in artifact.freestandingFunctions + artifact.globalVariables {
            add(name: function.name, location: function.location)
        }
    }

    func declaresName(_ name: String, onAnyLineIn lines: ClosedRange<Int>) -> Bool {
        linesByName[name.simpleNameComponent].map { $0.contains(where: lines.contains) } ?? false
    }

    var names: Set<String> { Set(linesByName.keys) }

    private mutating func add(_ type: TypeDeclaration) {
        add(name: type.name, location: type.location)
        for member in type.members {
            add(name: member.name, location: member.location)
        }
        for enumCase in type.enumCases {
            add(name: enumCase.name, location: enumCase.location)
        }
        for nested in type.nestedTypes {
            add(nested)
        }
    }

    private mutating func add(name: String, location: SourceLocation?) {
        guard let location, !name.isEmpty else { return }
        linesByName[name.simpleNameComponent, default: []].insert(location.line)
    }
}

extension String {

    /// The last component, so a C++ `Shop::total` matches the `total` member the extractor records.
    var simpleNameComponent: String {
        let separators: [String] = ["::", "."]
        return separators.reduce(self) { name, separator in
            name.components(separatedBy: separator).last ?? name
        }
    }
}
