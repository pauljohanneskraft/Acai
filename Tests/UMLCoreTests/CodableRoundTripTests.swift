import Testing
import Foundation
@testable import UMLCore

@Suite("Codable Round Trip Tests")
struct CodableRoundTripTests {

    @Test func sourceLocation() throws {
        let original = SourceLocation(filePath: "test.swift", line: 10, column: 5)
        let decoded = try roundTrip(original)
        #expect(original == decoded)
    }

    @Test func accessLevels() throws {
        for level in AccessLevel.allCases {
            let decoded = try roundTrip(level)
            #expect(level == decoded)
        }
    }

    @Test func modifiers() throws {
        for mod in Modifier.allCases {
            let decoded = try roundTrip(mod)
            #expect(mod == decoded)
        }
    }

    @Test func typeReference() throws {
        let original = TypeReference(
            name: "Dictionary",
            genericArguments: [
                TypeReference(name: "String"),
                TypeReference(name: "Array", genericArguments: [
                    TypeReference(name: "Int", isOptional: true)
                ], isArray: true)
            ]
        )
        let decoded = try roundTrip(original)
        #expect(original == decoded)
    }

    @Test func genericParameter() throws {
        let original = GenericParameter(
            name: "T",
            constraints: [
                GenericConstraint(kind: .conformance, type: TypeReference(name: "Codable")),
                GenericConstraint(kind: .superclass, type: TypeReference(name: "NSObject"))
            ]
        )
        let decoded = try roundTrip(original)
        #expect(original == decoded)
    }

    @Test func parameter() throws {
        let original = Parameter(
            externalName: "with",
            internalName: "name",
            type: TypeReference(name: "String"),
            defaultValue: "\"default\"",
            isVariadic: false,
            modifiers: [.borrowing]
        )
        let decoded = try roundTrip(original)
        #expect(original == decoded)
    }

    @Test func enumCase() throws {
        let original = EnumCase(
            name: "success",
            rawValue: nil,
            associatedValues: [
                Parameter(internalName: "value", type: TypeReference(name: "T"))
            ],
            location: SourceLocation(filePath: "Result.swift", line: 5, column: 10)
        )
        let decoded = try roundTrip(original)
        #expect(original == decoded)
    }

    @Test func member() throws {
        let original = Member(
            name: "fetchData",
            kind: .method,
            accessLevel: .public,
            modifiers: [.async, .throws],
            type: TypeReference(name: "Data", isOptional: true),
            parameters: [
                Parameter(internalName: "url", type: TypeReference(name: "URL"))
            ],
            genericParameters: [GenericParameter(name: "T")],
            isComputed: false,
            annotations: ["@discardableResult"]
        )
        let decoded = try roundTrip(original)
        #expect(original == decoded)
    }

    @Test func typeDeclaration() throws {
        let original = TypeDeclaration(
            id: "MyModule.MyClass",
            name: "MyClass",
            qualifiedName: "MyModule.MyClass",
            kind: .class,
            accessLevel: .public,
            modifiers: [.final],
            genericParameters: [GenericParameter(name: "T", constraints: [
                GenericConstraint(kind: .conformance, type: TypeReference(name: "Codable"))
            ])],
            inheritedTypes: [TypeReference(name: "BaseClass")],
            members: [
                Member(name: "value", kind: .property, accessLevel: .private,
                       type: TypeReference(name: "T"))
            ],
            enumCases: [],
            nestedTypes: [
                TypeDeclaration(id: "Inner", name: "Inner", qualifiedName: "MyModule.MyClass.Inner",
                                kind: .struct, accessLevel: .public)
            ],
            annotations: ["@Observable"],
            namespace: "MyModule",
            location: SourceLocation(filePath: "MyClass.swift", line: 1, column: 1)
        )
        let decoded = try roundTrip(original)
        #expect(original == decoded)
    }

    @Test func relationship() throws {
        let original = Relationship(
            kind: .inheritance,
            source: "Dog",
            target: "Animal",
            sourceLabel: "1",
            targetLabel: "*",
            label: "extends"
        )
        let decoded = try roundTrip(original)
        #expect(original == decoded)
    }

    @Test func relationshipKinds() throws {
        for kind in Relationship.Kind.allCases {
            let decoded = try roundTrip(kind)
            #expect(kind == decoded)
        }
    }

    @Test func codeArtifact() throws {
        let original = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["A.swift", "B.swift"], toolVersion: "1.0"),
            types: [
                TypeDeclaration(id: "Foo", name: "Foo", qualifiedName: "Foo", kind: .class, accessLevel: .public),
                TypeDeclaration(id: "Bar", name: "Bar", qualifiedName: "Bar", kind: .protocol, accessLevel: .public)
            ],
            relationships: [
                Relationship(kind: .conformance, source: "Foo", target: "Bar")
            ],
            freestandingFunctions: [
                Member(name: "helper", kind: .method, accessLevel: .internal)
            ]
        )
        let decoded = try roundTrip(original)
        #expect(original == decoded)
    }

    @Test func sourceLanguages() throws {
        // `SourceLanguage` is an open struct (no `.allCases`); round-trip the built-in raw values
        // plus an external one to prove the wire format is preserved for any language.
        let rawValues = ["swift", "kotlin", "java", "typeScript", "javaScript", "dart", "python"]
        for raw in rawValues {
            let lang = CodeArtifact.SourceLanguage(rawValue: raw)
            let decoded = try roundTrip(lang)
            #expect(lang == decoded)
            #expect(lang.rawValue == raw)
        }
    }

    @Test func merging() {
        let a = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["A.swift"]),
            types: [TypeDeclaration(id: "A", name: "A", qualifiedName: "A", kind: .class, accessLevel: .public)]
        )
        let b = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["B.swift"]),
            types: [TypeDeclaration(id: "B", name: "B", qualifiedName: "B", kind: .struct, accessLevel: .public)]
        )
        let merged = a.merging(with: b)
        #expect(merged.types.count == 2)
        #expect(merged.metadata.filePaths == ["A.swift", "B.swift"])
    }

    @Test func resolvingExtensions() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Test.swift"]),
            types: [
                TypeDeclaration(id: "Foo", name: "Foo", qualifiedName: "Foo", kind: .class, accessLevel: .public),
                TypeDeclaration(id: "extension.Foo", name: "Foo", qualifiedName: "Foo",
                                kind: .extension, accessLevel: .public,
                                inheritedTypes: [TypeReference(name: "Codable")],
                                members: [Member(name: "encode", kind: .method, accessLevel: .internal)],
                                extensionOf: "Foo")
            ]
        )
        let resolved = artifact.resolvingExtensions()
        #expect(resolved.types.count == 1)
        #expect(resolved.types[0].members.count == 1)
        #expect(resolved.types[0].members[0].name == "encode")
        #expect(resolved.relationships.contains {
            $0.kind == .conformance && $0.source == "Foo" && $0.target == "Codable"
        })
    }

    @Test func resolvingExtensionsDropsExternalBaseTypes() {
        // `extension SIMD3` where SIMD3 isn't defined in the codebase must not appear.
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Test.swift"]),
            types: [
                TypeDeclaration(id: "Foo", name: "Foo", qualifiedName: "Foo", kind: .class, accessLevel: .public),
                TypeDeclaration(
                    id: "extension.SIMD3", name: "SIMD3", qualifiedName: "SIMD3",
                    kind: .extension,
                    accessLevel: .public,
                    inheritedTypes: [TypeReference(name: "CustomProtocol")],
                    members: [Member(name: "magnitude", kind: .property, accessLevel: .internal)],
                    extensionOf: "SIMD3")
            ]
        )
        let resolved = artifact.resolvingExtensions()
        #expect(resolved.types.map(\.name) == ["Foo"])
        #expect(!resolved.relationships.contains { $0.source == "SIMD3" })
    }

    // MARK: - Helper

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
