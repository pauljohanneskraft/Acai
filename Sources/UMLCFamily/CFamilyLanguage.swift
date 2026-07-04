import UMLCore

// The identities and quirks of the C-family languages. C and C++ live in one target (like Java and
// Kotlin share `UMLJVM`) because they share their build systems (CMake/Make/Meson) and most of their
// tree-sitter grammar. Each still gets its own `SourceLanguage` constant and `LanguageConfiguration`
// so the agnostic engine classifies a file by exactly what it is.

extension CodeArtifact.SourceLanguage {
    public static let c = CodeArtifact.SourceLanguage(rawValue: "c")
    public static let cpp = CodeArtifact.SourceLanguage(rawValue: "cpp")
}

// The `configuration` requirement of `CodeParser` lives here (a UMLCore-only file) rather than in the
// parser files: those import `UMLTreeSitter`, which re-exports `SwiftTreeSitter`'s own
// `LanguageConfiguration`, so naming the type there is ambiguous.
extension CCodeParser {
    public var configuration: LanguageConfiguration { CFamilyDialect.c.configuration }
}

extension CppCodeParser {
    public var configuration: LanguageConfiguration { CFamilyDialect.cpp.configuration }
}

/// One of the two C-family dialects. Carries its own `SourceLanguage` and `LanguageConfiguration` so
/// the parser, extractor, and header classifier all drive off a single value rather than scattering
/// `if isCpp` branches.
enum CFamilyDialect: Sendable {
    case c
    case cpp

    /// The agnostic engine's identity for this dialect.
    var sourceLanguage: CodeArtifact.SourceLanguage {
        switch self {
        case .c:
            .c
        case .cpp:
            .cpp
        }
    }

    /// The per-language reference data injected into the agnostic enrichment pipeline.
    var configuration: LanguageConfiguration {
        switch self {
        case .c:
            LanguageConfiguration(
                primitiveTypeNames: Self.cPrimitives,
                collectionTypeNames: [],
                annotationStereotypes: [:],
                generatedCodeFilter: GeneratedCodeFilter(
                    displayName: "C Generated Types",
                    explanation: "Hides types from generated sources such as protobuf-c (.pb-c.h).",
                    fileSuffixes: [".pb-c.h", ".pb-c.c"],
                    typeNamePatterns: []
                ),
                excludedDirectories: Self.excludedDirectories,
                entryPointMarkers: EntryPointMarkers(methodNames: ["main"])
            )
        case .cpp:
            LanguageConfiguration(
                primitiveTypeNames: Self.cPrimitives.union([
                    "auto", "decltype", "std::nullptr_t", "std::size_t", "std::byte",
                    "std::string", "std::wstring", "std::string_view"
                ]),
                collectionTypeNames: Self.cppCollections,
                annotationStereotypes: [:],
                generatedCodeFilter: GeneratedCodeFilter(
                    displayName: "C++ Generated Types",
                    explanation: "Hides types from generated sources such as protobuf (.pb.h) and Qt moc files.",
                    fileSuffixes: [".pb.h", ".pb.cc", ".pb.cpp", ".moc"],
                    typeNamePatterns: []
                ),
                excludedDirectories: Self.excludedDirectories,
                entryPointMarkers: EntryPointMarkers(methodNames: ["main"])
            )
        }
    }

    /// Build-output / dependency directories common to C and C++ projects (CMake, Make, Meson, Ninja).
    static let excludedDirectories: Set<String> = [
        "build", "_build", "builddir", "out", "bin", "obj",
        "cmake-build-debug", "cmake-build-release", "CMakeFiles", ".cmake",
        "vcpkg_installed", "third_party", "Debug", "Release"
    ]

    /// C's built-in scalar types, including the `sized_type_specifier` spellings (`unsigned int`,
    /// `long long`, …) and the `<stdint.h>` / `<stddef.h>` fixed-width and pointer-sized aliases, so
    /// the enrichment pass never mistakes a primitive for a related node.
    private static let cPrimitives: Set<String> = [
        "void", "char", "short", "int", "long", "float", "double", "signed", "unsigned",
        "_Bool", "bool", "_Complex", "_Imaginary",
        "signed char", "unsigned char", "short int", "signed short", "unsigned short",
        "signed int", "unsigned int", "long int", "signed long", "unsigned long",
        "long long", "long long int", "unsigned long long", "long double",
        "size_t", "ssize_t", "ptrdiff_t", "intptr_t", "uintptr_t", "wchar_t", "wint_t",
        "int8_t", "int16_t", "int32_t", "int64_t",
        "uint8_t", "uint16_t", "uint32_t", "uint64_t",
        "int_least8_t", "int_least16_t", "int_least32_t", "int_least64_t",
        "uint_least8_t", "uint_least16_t", "uint_least32_t", "uint_least64_t",
        "int_fast8_t", "int_fast16_t", "int_fast32_t", "int_fast64_t",
        "uint_fast8_t", "uint_fast16_t", "uint_fast32_t", "uint_fast64_t",
        "intmax_t", "uintmax_t", "char16_t", "char32_t", "char8_t",
        "FILE", "va_list", "nullptr_t"
    ]

    private static let cppCollections: Set<String> = {
        let bare = [
            "vector", "array", "list", "forward_list", "deque", "set", "multiset",
            "map", "multimap", "unordered_set", "unordered_multiset",
            "unordered_map", "unordered_multimap", "stack", "queue", "priority_queue",
            "pair", "tuple", "optional", "variant", "span", "initializer_list",
            "unique_ptr", "shared_ptr", "weak_ptr"
        ]
        return Set(bare).union(bare.map { "std::\($0)" })
    }()
}
