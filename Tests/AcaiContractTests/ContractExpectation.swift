import Foundation

/// A feature's expected shape, plus the fields each language may state differently short of a waiver.
struct ContractExpectation: Decodable {
    var shape: ContractShape
    var languages: [String: LanguageAllowance]

    struct LanguageAllowance: Decodable, Equatable {
        enum Field: String, Decodable {
            /// A signature's own type and each of its parameters' types.
            case type
            case kind
        }

        var unchecked: Set<Field> = []
        /// Applied to the expectation only, so the language's own kind is still checked.
        var typeKinds: [String: String] = [:]

        /// Distinct from the normaliser's `?` for a type the parser failed to find.
        static let uncheckedToken = "#unchecked"

        enum CodingKeys: String, CodingKey {
            case unchecked, typeKinds
        }

        init(unchecked: Set<Field> = [], typeKinds: [String: String] = [:]) {
            self.unchecked = unchecked
            self.typeKinds = typeKinds
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            unchecked = Set(try container.decodeIfPresent([Field].self, forKey: .unchecked) ?? [])
            typeKinds = try container.decodeIfPresent([String: String].self, forKey: .typeKinds) ?? [:]
        }

        var isEmpty: Bool { unchecked.isEmpty && typeKinds.isEmpty }

        func expected(_ shape: ContractShape) -> ContractShape {
            comparable(kindsMapped(shape))
        }

        func actual(_ shape: ContractShape) -> ContractShape {
            comparable(shape)
        }

        private func kindsMapped(_ shape: ContractShape) -> ContractShape {
            guard !typeKinds.isEmpty else { return shape }
            var shape = shape
            shape.types = shape.types.map(kindsMapped(in:))
            return shape
        }

        private func kindsMapped(in declaration: ContractShape.Declaration) -> ContractShape.Declaration {
            var declaration = declaration
            declaration.kind = typeKinds[declaration.kind] ?? declaration.kind
            declaration.nested = declaration.nested.map(kindsMapped(in:))
            return declaration
        }

        private func comparable(_ shape: ContractShape) -> ContractShape {
            guard !unchecked.isEmpty else { return shape }
            var shape = shape
            shape.types = shape.types.map(erased(in:))
            shape.freeFunctions = shape.freeFunctions.map(erased(in:))
            shape.globals = shape.globals.map(erased(in:))
            return shape
        }

        private func erased(in declaration: ContractShape.Declaration) -> ContractShape.Declaration {
            var declaration = declaration
            if unchecked.contains(.kind) { declaration.kind = Self.uncheckedToken }
            declaration.members = declaration.members.map(erased(in:))
            declaration.nested = declaration.nested.map(erased(in:))
            return declaration
        }

        private func erased(in signature: ContractShape.Signature) -> ContractShape.Signature {
            guard unchecked.contains(.type) else { return signature }
            var signature = signature
            signature.type = nil
            signature.parameters = signature.parameters.map { parameter in
                "\(parameter.prefix { $0 != ":" }): \(Self.uncheckedToken)"
            }
            return signature
        }
    }

    enum CodingKeys: String, CodingKey {
        case languages
    }

    init(shape: ContractShape, languages: [String: LanguageAllowance] = [:]) {
        self.shape = shape
        self.languages = languages
    }

    /// The shape and the allowances share the file's top-level object.
    init(from decoder: any Decoder) throws {
        shape = try ContractShape(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        languages = try container.decodeIfPresent([String: LanguageAllowance].self, forKey: .languages) ?? [:]
    }

    func allowance(for language: ContractFeatureCorpus.Language) -> LanguageAllowance {
        languages[language.stem] ?? LanguageAllowance()
    }
}
