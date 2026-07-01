// swift-tools-version: 6.0

import PackageDescription

var optionalProducts: [Product] = []
var optionalTargets: [Target] = []
// Extra dependencies added to UMLCLI only on SwiftUI-capable hosts (macOS), where the
// SwiftUI-based image renderer (`UMLRender`) exists. Kept empty on Linux so the CLI builds.
var cliOptionalDependencies: [Target.Dependency] = []

#if canImport(SwiftUI)
// MARK: SwiftUI rendering library, shared by the app and the CLI image command.
optionalProducts.append(
    .library(name: "UMLRender", targets: ["UMLRender"])
)
optionalTargets.append(
    .target(
        name: "UMLRender",
        dependencies: [
            "UMLCore",
            "UMLDiagram",
        ]
    )
)
optionalTargets.append(
    .testTarget(name: "UMLRenderTests", dependencies: ["UMLRender", "UMLCore", "UMLLibrary", "UMLDiagram"])
)
cliOptionalDependencies.append(.target(name: "UMLRender", condition: .when(platforms: [.macOS])))

optionalProducts.append(
    .executable(
        name: "UMLApp",
        targets: ["UMLApp"]
    )
)
optionalTargets.append(
    .executableTarget(
        name: "UMLApp",
        dependencies: [
            "UMLCore",
            "UMLDiagram",
            "UMLDiff",
            "UMLConformance",
            "UMLLibrary",
            "UMLRender",
            .product(name: "Yams", package: "Yams"),
        ],
        exclude: ["Resources/Info.plist"],
        resources: [
            .process("Resources/Assets.xcassets"),
        ],
        linkerSettings: [
            // Embeds Info.plist into the binary so it runs as a GUI app
            .unsafeFlags([
                "-Xlinker", "-sectcreate",
                "-Xlinker", "__TEXT",
                "-Xlinker", "__info_plist",
                "-Xlinker", "Sources/UMLApp/Resources/Info.plist"
            ])
        ]
    )
)
optionalTargets.append(
    .testTarget(name: "UMLAppTests", dependencies: ["UMLApp", "UMLCore"])
)
#endif


let package = Package(
    name: "UML",
    platforms: [
        .macOS(.v15),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "UMLCore", targets: ["UMLCore"]),
        .library(name: "UMLTreeSitter", targets: ["UMLTreeSitter"]),
        .library(name: "UMLSwift", targets: ["UMLSwift"]),
        .library(name: "UMLJVM", targets: ["UMLJVM"]),
        .library(name: "UMLJS", targets: ["UMLJS"]),
        .library(name: "UMLDart", targets: ["UMLDart"]),
        .library(name: "UMLPython", targets: ["UMLPython"]),
        .library(name: "UMLCFamily", targets: ["UMLCFamily"]),
        .library(name: "UMLCSharp", targets: ["UMLCSharp"]),
        .library(name: "UMLDiagram", targets: ["UMLDiagram"]),
        .library(name: "UMLDiff", targets: ["UMLDiff"]),
        .library(name: "UMLConformance", targets: ["UMLConformance"]),
        .library(name: "UMLLibrary", targets: ["UMLLibrary"]),
    ] + optionalProducts,
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", from: "0.9.0"),
        .package(url: "https://github.com/fwcd/tree-sitter-kotlin", from: "0.3.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-typescript", from: "0.21.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-java", from: "0.21.0"),
        .package(url: "https://github.com/UserNobody14/tree-sitter-dart", branch: "master"),
        // Pinned exactly: the grammar's `scanner.c` (vendored in the `CPythonScanner` target to
        // work around the grammar's broken SwiftPM manifest, which never compiles `scanner.c`) is
        // coupled to this version's `parser.c` external-token table and must match it exactly.
        .package(url: "https://github.com/tree-sitter/tree-sitter-python", exact: "0.25.0"),
        // C and C++ share the `UMLCFamily` target (like Java+Kotlin share `UMLJVM`). Both grammars
        // ship working SwiftPM manifests — tree-sitter-cpp compiles its own `src/scanner.c`, so
        // (unlike Python) no vendored scanner target is needed.
        .package(url: "https://github.com/tree-sitter/tree-sitter-c", from: "0.24.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-cpp", from: "0.23.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-c-sharp", from: "0.23.5"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/jpsim/Yams", from: "5.0.0"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.4.0"),
    ],
    targets: [
        // MARK: Core models
        .target(
            name: "UMLCore",
            dependencies: []
        ),

        // MARK: Shared tree-sitter helpers (re-exports SwiftTreeSitter)
        .target(
            name: "UMLTreeSitter",
            dependencies: [
                "UMLCore",
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
            ]
        ),

        // MARK: Language parsers
        .target(
            name: "UMLSwift",
            dependencies: [
                "UMLCore",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftParserDiagnostics", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "UMLJS",
            dependencies: [
                "UMLCore",
                "UMLTreeSitter",
                .product(name: "TreeSitterTypeScript", package: "tree-sitter-typescript"),
            ]
        ),
        // MARK: JVM languages (Java + Kotlin) — one target because they share the JVM build
        // systems and the `JVMBuildSystemDetector`.
        .target(
            name: "UMLJVM",
            dependencies: [
                "UMLCore",
                "UMLTreeSitter",
                .product(name: "TreeSitterJava", package: "tree-sitter-java"),
                .product(name: "TreeSitterKotlin", package: "tree-sitter-kotlin"),
            ]
        ),
        .target(
            name: "UMLDart",
            dependencies: [
                "UMLCore",
                "UMLTreeSitter",
                .product(name: "TreeSitterDart", package: "tree-sitter-dart"),
            ]
        ),
        // Vendors *only* the grammar's `scanner.c` (+ its three small headers) so the external
        // scanner symbols that `parser.c` references are linked. The upstream grammar's SwiftPM
        // manifest never compiles `scanner.c` (its relative `fileExists` check fails for a remote
        // dependency — see tree-sitter/tree-sitter-python#330, still unmerged). Drop this target and
        // depend on the official package directly once that fix ships in a release.
        .target(name: "CPythonScanner", exclude: ["LICENSE"]),
        .target(
            name: "UMLPython",
            dependencies: [
                "UMLCore",
                "UMLTreeSitter",
                "CPythonScanner",
                .product(name: "TreeSitterPython", package: "tree-sitter-python"),
            ]
        ),
        // MARK: C-family languages (C + C++) — one target because they share the C/C++ build
        // systems (CMake/Make/Meson) + `CFamilyBuildSystemDetector` and most of their tree-sitter
        // grammar (tree-sitter-cpp reuses tree-sitter-c's node types).
        .target(
            name: "UMLCFamily",
            dependencies: [
                "UMLCore",
                "UMLTreeSitter",
                .product(name: "TreeSitterC", package: "tree-sitter-c"),
                .product(name: "TreeSitterCPP", package: "tree-sitter-cpp"),
            ]
        ),
        .target(
            name: "UMLCSharp",
            dependencies: [
                "UMLCore",
                "UMLTreeSitter",
                .product(name: "TreeSitterCSharp", package: "tree-sitter-c-sharp"),
            ]
        ),

        // MARK: DOT/Graphviz diagram generator
        .target(
            name: "UMLDiagram",
            dependencies: ["UMLCore"]
        ),

        // MARK: Semantic architecture diffing — agnostic graph/metric comparison of two artifacts,
        // plus per-diagram-model (sequence/state/package/call-graph) deltas (depends on UMLDiagram
        // for those models; still names no language).
        .target(
            name: "UMLDiff",
            dependencies: ["UMLCore", "UMLDiagram"]
        ),

        // MARK: Architecture conformance / fitness functions — agnostic rule evaluation.
        .target(
            name: "UMLConformance",
            dependencies: ["UMLCore"]
        ),

        // MARK: Composition root — the only target that names the built-in languages. Wires the
        // parsers + their detectors into `AnalysisService.standard` and re-exports the agnostic API.
        .target(
            name: "UMLLibrary",
            dependencies: [
                "UMLCore",
                "UMLDiagram",
                "UMLDiff",
                "UMLConformance",
                "UMLSwift",
                "UMLJS",
                "UMLJVM",
                "UMLDart",
                "UMLPython",
                "UMLCFamily",
                "UMLCSharp",
            ]
        ),

        // MARK: CLI tool
        .executableTarget(
            name: "UMLCLI",
            dependencies: [
                "UMLCore",
                "UMLDiagram",
                "UMLDiff",
                "UMLConformance",
                "UMLLibrary",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Yams", package: "Yams"),
            ] + cliOptionalDependencies,
        ),

        // MARK: Tests
        .testTarget(name: "UMLCoreTests", dependencies: ["UMLCore"]),
        .testTarget(name: "UMLSwiftTests", dependencies: ["UMLSwift", "UMLCore"]),
        .testTarget(name: "UMLJSTests", dependencies: ["UMLJS", "UMLCore"]),
        .testTarget(name: "UMLJVMTests", dependencies: ["UMLJVM", "UMLCore"]),
        .testTarget(name: "UMLDartTests", dependencies: ["UMLDart", "UMLCore"]),
        .testTarget(name: "UMLPythonTests", dependencies: ["UMLPython", "UMLCore"]),
        .testTarget(name: "UMLCFamilyTests", dependencies: ["UMLCFamily", "UMLCore"]),
        .testTarget(name: "UMLCSharpTests", dependencies: ["UMLCSharp", "UMLCore"]),
        .testTarget(name: "UMLDiagramTests", dependencies: ["UMLDiagram", "UMLCore"]),
        .testTarget(name: "UMLDiffTests", dependencies: ["UMLDiff", "UMLCore", "UMLDiagram"]),
        .testTarget(name: "UMLConformanceTests", dependencies: ["UMLConformance", "UMLCore"]),
        .testTarget(name: "UMLLibraryTests", dependencies: ["UMLLibrary", "UMLDiagram"]),
        .testTarget(name: "UMLCLITests", dependencies: ["UMLCLI", "UMLCore"]),

        // MARK: Golden-file regression tests for the checked-in Examples/ exports.
        // Cross-platform (no UMLRender dependency); the PNG checks live in UMLRenderTests.
        .testTarget(name: "UMLExamplesTests", dependencies: ["UMLLibrary", "UMLDiagram", "UMLDiff", "UMLCore"])
    ] + optionalTargets
)
