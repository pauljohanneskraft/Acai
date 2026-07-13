import Foundation

/// Normalizes a raw type-reference string to the producer contract's required "simple name":
/// generic arguments stripped (`Foo<T>` → `Foo`), namespace qualifiers stripped (`a.b.Foo` → `Foo`).
/// A single shared implementation so no language plugin reimplements this rule slightly differently.
public struct SimpleTypeName: Sendable {
    public let raw: String

    public init(_ raw: String) {
        self.raw = raw
    }

    public var simpleName: String {
        let withoutGenerics = raw.prefix { $0 != "<" }
        let segments = withoutGenerics.split(separator: ".")
        return String(segments.last ?? withoutGenerics[...]).trimmingCharacters(in: .whitespaces)
    }
}
