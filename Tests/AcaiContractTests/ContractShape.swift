import Foundation
import AcaiCore

/// The cross-language projection of a `CodeArtifact` the feature matrix compares.
///
/// An absent key decodes as empty and an empty collection encodes to nothing, so a hand-written
/// `.expected.json` states only what the feature is about — and the failure message prints both sides
/// in that same compact form.
struct ContractShape: Codable, Equatable {
    var types: [Declaration] = []
    var freeFunctions: [Signature] = []
    var globals: [Signature] = []
    var relationships: [Edge] = []

    struct Declaration: Codable, Equatable {
        var name: String
        var kind: String
        /// UML access symbol (`+ # ~ -`) — the vocabulary the diagram layer consumes, and the only
        /// form in which Swift `internal` and Java package-private are the same thing.
        var access: String
        var modifiers: [String] = []
        var generics: [String] = []
        var annotations: [String] = []
        var supertypes: [String] = []
        var members: [Signature] = []
        var enumCases: [String] = []
        var nested: [Declaration] = []

        enum CodingKeys: String, CodingKey {
            case name, kind, access, modifiers, generics, annotations, supertypes, members, enumCases, nested
        }

        init(
            name: String, kind: String, access: String, modifiers: [String] = [], generics: [String] = [],
            annotations: [String] = [], supertypes: [String] = [], members: [Signature] = [],
            enumCases: [String] = [], nested: [Declaration] = []
        ) {
            self.name = name
            self.kind = kind
            self.access = access
            self.modifiers = modifiers
            self.generics = generics
            self.annotations = annotations
            self.supertypes = supertypes
            self.members = members
            self.enumCases = enumCases
            self.nested = nested
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            kind = try container.decode(String.self, forKey: .kind)
            access = try container.decode(String.self, forKey: .access)
            modifiers = try container.decodeIfPresent([String].self, forKey: .modifiers) ?? []
            generics = try container.decodeIfPresent([String].self, forKey: .generics) ?? []
            annotations = try container.decodeIfPresent([String].self, forKey: .annotations) ?? []
            supertypes = try container.decodeIfPresent([String].self, forKey: .supertypes) ?? []
            members = try container.decodeIfPresent([Signature].self, forKey: .members) ?? []
            enumCases = try container.decodeIfPresent([String].self, forKey: .enumCases) ?? []
            nested = try container.decodeIfPresent([Declaration].self, forKey: .nested) ?? []
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(kind, forKey: .kind)
            try container.encode(access, forKey: .access)
            try container.encodeIfNotEmpty(modifiers, forKey: .modifiers)
            try container.encodeIfNotEmpty(generics, forKey: .generics)
            try container.encodeIfNotEmpty(annotations, forKey: .annotations)
            try container.encodeIfNotEmpty(supertypes, forKey: .supertypes)
            try container.encodeIfNotEmpty(members, forKey: .members)
            try container.encodeIfNotEmpty(enumCases, forKey: .enumCases)
            try container.encodeIfNotEmpty(nested, forKey: .nested)
        }
    }

    /// A member, free function or global. `role` is the normalised `MemberKind`: a constructor is
    /// `constructor` whatever the language spells it, which is the point of the projection.
    struct Signature: Codable, Equatable {
        var name: String
        var role: String
        var access: String
        var modifiers: [String] = []
        var annotations: [String] = []
        /// Return type of a method, declared type of a property. `#primitive`/`#collection` where the
        /// language's own configuration classifies it as one.
        var type: String?
        /// `name: Type`, in declaration order (the one thing in a signature that is never reordered).
        var parameters: [String] = []
        /// `Receiver.method` for a resolved call, `.method` for a self-dispatch.
        var calls: [String] = []
        var reads: [String] = []

        enum CodingKeys: String, CodingKey {
            case name, role, access, modifiers, annotations, type, parameters, calls, reads
        }

        init(
            name: String, role: String, access: String, modifiers: [String] = [],
            annotations: [String] = [], type: String? = nil, parameters: [String] = [],
            calls: [String] = [], reads: [String] = []
        ) {
            self.name = name
            self.role = role
            self.access = access
            self.modifiers = modifiers
            self.annotations = annotations
            self.type = type
            self.parameters = parameters
            self.calls = calls
            self.reads = reads
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            role = try container.decode(String.self, forKey: .role)
            access = try container.decode(String.self, forKey: .access)
            modifiers = try container.decodeIfPresent([String].self, forKey: .modifiers) ?? []
            annotations = try container.decodeIfPresent([String].self, forKey: .annotations) ?? []
            type = try container.decodeIfPresent(String.self, forKey: .type)
            parameters = try container.decodeIfPresent([String].self, forKey: .parameters) ?? []
            calls = try container.decodeIfPresent([String].self, forKey: .calls) ?? []
            reads = try container.decodeIfPresent([String].self, forKey: .reads) ?? []
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(role, forKey: .role)
            try container.encode(access, forKey: .access)
            try container.encodeIfNotEmpty(modifiers, forKey: .modifiers)
            try container.encodeIfNotEmpty(annotations, forKey: .annotations)
            try container.encodeIfPresent(type, forKey: .type)
            try container.encodeIfNotEmpty(parameters, forKey: .parameters)
            try container.encodeIfNotEmpty(calls, forKey: .calls)
            try container.encodeIfNotEmpty(reads, forKey: .reads)
        }
    }

    struct Edge: Codable, Equatable {
        var kind: String
        var source: String
        var target: String
        var label: String?
        var multiplicity: String?
    }

    enum CodingKeys: String, CodingKey {
        case types, freeFunctions, globals, relationships
    }

    init(
        types: [Declaration] = [], freeFunctions: [Signature] = [], globals: [Signature] = [],
        relationships: [Edge] = []
    ) {
        self.types = types
        self.freeFunctions = freeFunctions
        self.globals = globals
        self.relationships = relationships
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        types = try container.decodeIfPresent([Declaration].self, forKey: .types) ?? []
        freeFunctions = try container.decodeIfPresent([Signature].self, forKey: .freeFunctions) ?? []
        globals = try container.decodeIfPresent([Signature].self, forKey: .globals) ?? []
        relationships = try container.decodeIfPresent([Edge].self, forKey: .relationships) ?? []
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfNotEmpty(types, forKey: .types)
        try container.encodeIfNotEmpty(freeFunctions, forKey: .freeFunctions)
        try container.encodeIfNotEmpty(globals, forKey: .globals)
        try container.encodeIfNotEmpty(relationships, forKey: .relationships)
    }

    /// The form a failure message prints and a `.expected.json` is written in.
    var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8) else {
            return "<unencodable>"
        }
        return text
    }
}

extension KeyedEncodingContainer {
    /// Keeps an empty collection out of the encoded form, matching the lenient decoding above.
    mutating func encodeIfNotEmpty<T: Encodable & Collection>(_ value: T, forKey key: Key) throws {
        guard !value.isEmpty else { return }
        try encode(value, forKey: key)
    }
}
