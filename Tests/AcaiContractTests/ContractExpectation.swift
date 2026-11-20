import Foundation

/// A feature's hand-written `<feature>.expected.json`: the one shape every language has to normalise
/// to, plus the per-language allowances for a language that expresses the feature in its own
/// vocabulary.
///
/// An allowance is the middle ground a waiver used to swallow. A waiver says "this language cannot
/// express the feature at all" and removes the language from the feature entirely; an allowance says
/// "this language expresses it, and here is the one field it spells differently" — so everything else
/// the feature is about is still compared. JavaScript carries no type annotation, which is a reason to
/// stop checking `type`, not a reason to stop checking that a constructor is a constructor.
struct ContractExpectation: Decodable {
    var shape: ContractShape
    var languages: [String: LanguageAllowance]

    /// What one language is allowed to differ in, short of waiving the whole feature.
    struct LanguageAllowance: Decodable, Equatable {
        /// A field of the projection a language may be excused from stating.
        enum Field: String, Decodable {
            /// Every declared type: a signature's own type and the type of each of its parameters.
            case type
            /// A declaration's UML stereotype.
            case kind
        }

        /// Fields this language cannot state, compared on neither side.
        var unchecked: Set<Field> = []
        /// The kind this language naturally uses where the expectation names another — C `struct` for
        /// a class-like type. Applied to the expectation, so the language's own kind is still checked.
        var typeKinds: [String: String] = [:]

        /// The placeholder an unchecked field is compared as on both sides. Distinct from the `?` the
        /// normaliser writes for a parameter whose type the parser genuinely did not find, so an
        /// allowance can never be mistaken for a parse failure.
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

        /// The expectation as this language states it: its own kinds first, then the fields it cannot
        /// state at all.
        func expected(_ shape: ContractShape) -> ContractShape {
            comparable(kindsMapped(shape))
        }

        /// The language's own shape, with the same unstatable fields removed.
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

    /// The shape and the allowances share the file's top-level object, so the shape decodes from the
    /// same container rather than from a nested key.
    init(from decoder: any Decoder) throws {
        shape = try ContractShape(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        languages = try container.decodeIfPresent([String: LanguageAllowance].self, forKey: .languages) ?? [:]
    }

    func allowance(for language: ContractFeatureCorpus.Language) -> LanguageAllowance {
        languages[language.stem] ?? LanguageAllowance()
    }
}
