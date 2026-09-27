import Foundation
@testable import AcaiCore

/// The shapes a legacy-decode snapshot is recorded from: broad enough that every `Codable` case a
/// persisted `CodeArtifact` or `AnalysisStore.Entry` can hold appears in the JSON, because the
/// corpus only protects the fields it actually contains.
struct LegacyCorpusSample {
    /// Fixed so a recorded snapshot carries the same values a decode assertion checks for.
    let modificationDate = Date(timeIntervalSince1970: 1_700_000_000)

    var artifact: CodeArtifact {
        CodeArtifact(
            metadata: CodeArtifact.Metadata(
                sourceLanguage: .swift,
                filePaths: ["Service.swift", "Kind.swift"],
                toolVersion: "corpus-1.0",
                parseDiagnostics: [
                    ParseDiagnostic(
                        location: SourceLocation(filePath: "Kind.swift", line: 9, column: 2),
                        kind: .missing,
                        message: "unexpected token"
                    )
                ]
            ),
            types: [service, kindEnum, serviceExtension] + everyTypeKind,
            relationships: everyRelationshipKind,
            freestandingFunctions: [freestandingFunction],
            globalVariables: [globalVariable]
        )
    }

    var gitFingerprint: CodeStateFingerprint {
        .git(headCommitSHA: "0f1e2d3c4b5a69788796a5b4c3d2e1f001122334", isDirty: true)
    }

    var fileSystemFingerprint: CodeStateFingerprint {
        .fileSystem(latestModification: modificationDate, fileCount: 2, contentDigest: 0xdead_beef_cafe_f00d)
    }

    // MARK: - Types

    private var service: TypeDeclaration {
        TypeDeclaration(
            id: "Corpus.Service",
            name: "Service",
            qualifiedName: "Corpus.Service",
            kind: .class,
            accessLevel: .public,
            modifiers: [.final, .open],
            genericParameters: [
                GenericParameter(name: "T", constraints: [
                    GenericConstraint(kind: .conformance, type: TypeReference(name: "Codable")),
                    GenericConstraint(kind: .superclass, type: TypeReference(name: "NSObject")),
                    GenericConstraint(kind: .sameType, type: TypeReference(name: "Element"))
                ])
            ],
            associatedTypes: [GenericParameter(name: "Output")],
            inheritedTypes: [
                TypeReference(name: "Base"),
                TypeReference(
                    name: "Dictionary",
                    genericArguments: [
                        TypeReference(name: "String"),
                        TypeReference(name: "Item", isOptional: true, isArray: true)
                    ]
                )
            ],
            members: [storedProperty, methodWithEveryModifier, initializer, deinitializer, subscriptMember],
            nestedTypes: [
                TypeDeclaration(
                    id: "Corpus.Service.Inner",
                    name: "Inner",
                    qualifiedName: "Corpus.Service.Inner",
                    kind: .struct,
                    accessLevel: .filePrivate,
                    namespace: "Corpus.Service",
                    location: SourceLocation(filePath: "Service.swift", line: 40, column: 5),
                    sourceLanguage: .swift
                )
            ],
            annotations: ["@Observable", "@MainActor"],
            namespace: "Corpus",
            location: SourceLocation(filePath: "Service.swift", line: 3, column: 1),
            sourceLanguage: .swift
        )
    }

    private var storedProperty: Member {
        Member(
            name: "store",
            kind: .property,
            accessLevel: .internal,
            setAccessLevel: .private,
            modifiers: [.lazy, .weak],
            type: TypeReference(name: "Store", isOptional: true),
            isComputed: false,
            annotations: ["@Published"],
            location: SourceLocation(filePath: "Service.swift", line: 5, column: 5),
            initialValue: VariableAssignment.Value(kind: .nilLiteral, text: "nil"),
            referencedTypeNames: ["Store"]
        )
    }

    /// Every `Modifier` raw value in one member, so a renamed or dropped case fails to decode here.
    private var methodWithEveryModifier: Member {
        Member(
            name: "run",
            kind: .method,
            accessLevel: .protected,
            modifiers: Modifier.allCases,
            type: TypeReference(name: "Output", isOptional: true),
            parameters: [
                Parameter(
                    externalName: "with",
                    internalName: "input",
                    type: TypeReference(name: "Input"),
                    defaultValue: "Input()",
                    isVariadic: true,
                    modifiers: [.borrowing]
                )
            ],
            genericParameters: [GenericParameter(name: "U")],
            annotations: ["@discardableResult"],
            location: SourceLocation(filePath: "Service.swift", line: 12, column: 5),
            callSites: [
                CallSite(receiver: .selfDispatch, methodName: "step"),
                CallSite(
                    receiver: .type("Store"),
                    methodName: "save",
                    location: SourceLocation(filePath: "Service.swift", line: 14, column: 9)
                ),
                CallSite(receiver: .free, methodName: "log"),
                CallSite(receiver: .unknown, methodName: "dynamicCall")
            ],
            assignments: [
                VariableAssignment(
                    targetName: "state",
                    op: .assign,
                    value: VariableAssignment.Value(kind: .enumCase, text: "loading", receiverTypeName: "Kind"),
                    location: SourceLocation(filePath: "Service.swift", line: 15, column: 9)
                ),
                VariableAssignment(
                    targetName: "counter",
                    targetReceiver: "Metrics",
                    op: .compound,
                    value: VariableAssignment.Value(kind: .numericLiteral, text: "1")
                ),
                VariableAssignment(
                    targetName: "title",
                    op: .assign,
                    value: VariableAssignment.Value(kind: .stringLiteral, text: "\"idle\"")
                ),
                VariableAssignment(
                    targetName: "isReady",
                    op: .assign,
                    value: VariableAssignment.Value(kind: .booleanLiteral, text: "true")
                ),
                VariableAssignment(
                    targetName: "result",
                    op: .assign,
                    value: VariableAssignment.Value(kind: .expression, text: "compute()")
                )
            ],
            fieldReads: [
                FieldAccess(name: "state"),
                FieldAccess(
                    name: "counter",
                    receiver: "Metrics",
                    location: SourceLocation(filePath: "Service.swift", line: 16, column: 13)
                )
            ],
            referencedTypeNames: ["Input", "Output"],
            cyclomaticComplexity: 7
        )
    }

    private var initializer: Member {
        Member(name: "init", kind: .initializer, accessLevel: .packagePrivate, modifiers: [.convenience])
    }

    private var deinitializer: Member {
        Member(name: "deinit", kind: .deinitializer, accessLevel: .private)
    }

    private var subscriptMember: Member {
        Member(
            name: "subscript",
            kind: .subscript,
            accessLevel: .open,
            type: TypeReference(name: "Item"),
            parameters: [Parameter(internalName: "index", type: TypeReference(name: "Int"))],
            isComputed: true
        )
    }

    private var kindEnum: TypeDeclaration {
        TypeDeclaration(
            id: "Corpus.Kind",
            name: "Kind",
            qualifiedName: "Corpus.Kind",
            kind: .enum,
            accessLevel: .public,
            modifiers: [.indirect],
            enumCases: [
                EnumCase(
                    name: "loading",
                    location: SourceLocation(filePath: "Kind.swift", line: 2, column: 5)
                ),
                EnumCase(name: "named", rawValue: "NAMED"),
                EnumCase(
                    name: "failed",
                    associatedValues: [
                        Parameter(internalName: "error", type: TypeReference(name: "Error")),
                        Parameter(externalName: "retries", internalName: "count", type: TypeReference(name: "Int"))
                    ]
                )
            ],
            namespace: "Corpus",
            location: SourceLocation(filePath: "Kind.swift", line: 1, column: 1),
            sourceLanguage: .swift
        )
    }

    private var serviceExtension: TypeDeclaration {
        TypeDeclaration(
            id: "extension.Corpus.Service",
            name: "Service",
            qualifiedName: "Corpus.Service",
            kind: .extension,
            accessLevel: .internal,
            inheritedTypes: [TypeReference(name: "CustomStringConvertible")],
            members: [Member(name: "description", kind: .property, accessLevel: .public, isComputed: true)],
            extensionOf: "Corpus.Service",
            location: SourceLocation(filePath: "Service.swift", line: 60, column: 1),
            sourceLanguage: .swift
        )
    }

    /// One declaration per `TypeKind`, so every raw value is pinned by the corpus.
    private var everyTypeKind: [TypeDeclaration] {
        TypeKind.allCases.map { kind in
            TypeDeclaration(
                id: "Corpus.Kinds.\(kind.rawValue)",
                name: kind.rawValue,
                qualifiedName: "Corpus.Kinds.\(kind.rawValue)",
                kind: kind,
                accessLevel: .internal,
                namespace: "Corpus.Kinds"
            )
        }
    }

    /// One edge per `Relationship.Kind`, same reason as `everyTypeKind`.
    private var everyRelationshipKind: [Relationship] {
        Relationship.Kind.allCases.map { kind in
            Relationship(
                kind: kind,
                source: "Corpus.Service",
                target: "Corpus.\(kind.rawValue)Target",
                sourceLabel: "1",
                targetLabel: "0..*",
                label: kind.rawValue,
                origin: "Service.swift"
            )
        }
    }

    private var freestandingFunction: Member {
        Member(
            name: "makeService",
            kind: .method,
            accessLevel: .public,
            type: TypeReference(name: "Service"),
            location: SourceLocation(filePath: "Service.swift", line: 70, column: 1),
            callSites: [CallSite(receiver: .type("Corpus.Service"), methodName: "init")],
            cyclomaticComplexity: 1
        )
    }

    private var globalVariable: Member {
        Member(
            name: "sharedLimit",
            kind: .property,
            accessLevel: .internal,
            modifiers: [.static],
            type: TypeReference(name: "Int"),
            location: SourceLocation(filePath: "Service.swift", line: 1, column: 1),
            initialValue: VariableAssignment.Value(kind: .numericLiteral, text: "42")
        )
    }
}
