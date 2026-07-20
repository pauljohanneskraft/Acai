// swift-tools-version: 6.0

import PackageDescription

var optionalProducts: [Product] = []
var optionalTargets: [Target] = []
// Extra dependencies added to AcaiCLI only on SwiftUI-capable hosts (macOS), where the
// SwiftUI-based image renderer (`AcaiRender`) exists. Kept empty on Linux so the CLI builds.
var cliOptionalDependencies: [Target.Dependency] = []
// Same, for AcaiMCP: the `acai_image` tool links `AcaiRender` on macOS; empty on Linux.
var mcpOptionalDependencies: [Target.Dependency] = []

#if canImport(SwiftUI)
// MARK: SwiftUI rendering library, shared by the app and the CLI image command.
optionalProducts.append(
    .library(name: "AcaiRender", targets: ["AcaiRender"])
)
optionalTargets.append(
    .target(
        name: "AcaiRender",
        dependencies: [
            "AcaiCore",
            "AcaiDiagram",
            "AcaiDiff",
        ]
    )
)
optionalTargets.append(
    .testTarget(name: "AcaiRenderTests", dependencies: ["AcaiRender", "AcaiCore", "AcaiLibrary", "AcaiDiagram"])
)
cliOptionalDependencies.append(.target(name: "AcaiRender", condition: .when(platforms: [.macOS])))
mcpOptionalDependencies.append(.target(name: "AcaiRender", condition: .when(platforms: [.macOS])))

// A library (not an executable): the real app entry points live in the XcodeGen-generated
// project under `App/`, one per platform, each owning its own Info.plist/entitlements/asset
// catalog and just instantiating `ProjectBrowserView` from this library. See `App/project.yml`.
optionalProducts.append(
    .library(name: "AcaiApp", targets: ["AcaiApp"])
)
optionalTargets.append(
    .target(
        name: "AcaiApp",
        dependencies: [
            "AcaiCore",
            "AcaiDiagram",
            "AcaiDiff",
            "AcaiQuality",
            "AcaiLibrary",
            "AcaiRender",
            .product(name: "Yams", package: "Yams"),
            // Reads the zip GitHub serves for `.../zipball/{ref}` when cloning a repository
            // in-app (see `Sources/AcaiApp/GitHub`). Wraps minizip-ng (zlib-licensed, same
            // lineage as zlib's own `contrib/minizip`), no bundled executable.
            .product(name: "ZipArchive", package: "ZipArchive"),
        ]
    )
)
optionalTargets.append(
    .testTarget(
        name: "AcaiAppTests",
        // AcaiRender/AcaiDiagram: Layer 1 view-snapshot tests (`ViewSnapshot.swift`) render real
        // `AcaiApp` views via `AcaiRender`'s `DiagramImageRenderer` and construct
        // `ClassDiagramConfiguration` fixtures directly — see `TESTING_ARCHITECTURE.md`.
        dependencies: [
            "AcaiApp", "AcaiCore", "AcaiRender", "AcaiDiagram",
            .product(name: "ZipArchive", package: "ZipArchive"),
        ],
        // Layer 1's committed goldens (read by file path, not `Bundle.module` — see
        // `ViewSnapshot.swift`); declared so SwiftPM doesn't warn about unhandled non-Swift files.
        resources: [.copy("__Snapshots__")]
    )
)
#endif


let package = Package(
    name: "Acai",
    platforms: [
        .macOS(.v15),
        // v17, not v16: `AcaiApp` uses `.inspector()` (iOS 17+/macOS 13+, the latter already
        // satisfied by the v15 floor above) for its canvas/sidebar layout. The actual shipped iOS
        // app targets a much newer OS (see `App/project.yml`) — this is just the floor the SPM
        // package as a whole promises to support, kept as low as the APIs in use allow so
        // `AcaiCLI`/`AcaiMCP`'s wider compatibility isn't affected by the app's own requirements.
        .iOS(.v17),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "AcaiCore", targets: ["AcaiCore"]),
        .library(name: "AcaiTreeSitter", targets: ["AcaiTreeSitter"]),
        .library(name: "AcaiSwift", targets: ["AcaiSwift"]),
        .library(name: "AcaiJVM", targets: ["AcaiJVM"]),
        .library(name: "AcaiJS", targets: ["AcaiJS"]),
        .library(name: "AcaiDart", targets: ["AcaiDart"]),
        .library(name: "AcaiPython", targets: ["AcaiPython"]),
        .library(name: "AcaiCFamily", targets: ["AcaiCFamily"]),
        .library(name: "AcaiDiagram", targets: ["AcaiDiagram"]),
        .library(name: "AcaiDiff", targets: ["AcaiDiff"]),
        .library(name: "AcaiQuality", targets: ["AcaiQuality"]),
        .library(name: "AcaiLibrary", targets: ["AcaiLibrary"]),
        .executable(name: "AcaiMCP", targets: ["AcaiMCP"]),
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
        // C and C++ share the `AcaiCFamily` target (like Java+Kotlin share `AcaiJVM`). Both grammars
        // ship working SwiftPM manifests — tree-sitter-cpp compiles its own `src/scanner.c`, so
        // (unlike Python) no vendored scanner target is needed.
        .package(url: "https://github.com/tree-sitter/tree-sitter-c", from: "0.24.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-cpp", from: "0.23.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/jpsim/Yams", from: "5.0.0"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.4.0"),
        // The official Swift MCP SDK — the JSON-RPC/stdio transport behind the `AcaiMCP` entry point.
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk", from: "0.12.1"),
        // Zip extraction for in-app GitHub repository cloning (`AcaiApp`'s `GitHub/` sources) —
        // wraps minizip-ng, not a general dependency of the analysis engine.
        .package(url: "https://github.com/ZipArchive/ZipArchive", from: "2.5.5"),
    ],
    targets: [
        // MARK: Core models
        .target(
            name: "AcaiCore",
            dependencies: []
        ),

        // MARK: Shared tree-sitter helpers (re-exports SwiftTreeSitter)
        .target(
            name: "AcaiTreeSitter",
            dependencies: [
                "AcaiCore",
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
            ]
        ),

        // MARK: Language parsers
        .target(
            name: "AcaiSwift",
            dependencies: [
                "AcaiCore",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftParserDiagnostics", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "AcaiJS",
            dependencies: [
                "AcaiCore",
                "AcaiTreeSitter",
                .product(name: "TreeSitterTypeScript", package: "tree-sitter-typescript"),
            ]
        ),
        // MARK: JVM languages (Java + Kotlin) — one target because they share the JVM build
        // systems and the `JVMBuildSystemDetector`.
        .target(
            name: "AcaiJVM",
            dependencies: [
                "AcaiCore",
                "AcaiTreeSitter",
                .product(name: "TreeSitterJava", package: "tree-sitter-java"),
                .product(name: "TreeSitterKotlin", package: "tree-sitter-kotlin"),
            ]
        ),
        .target(
            name: "AcaiDart",
            dependencies: [
                "AcaiCore",
                "AcaiTreeSitter",
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
            name: "AcaiPython",
            dependencies: [
                "AcaiCore",
                "AcaiTreeSitter",
                "CPythonScanner",
                .product(name: "TreeSitterPython", package: "tree-sitter-python"),
            ]
        ),
        // MARK: C-family languages (C + C++) — one target because they share the C/C++ build
        // systems (CMake/Make/Meson) + `CFamilyBuildSystemDetector` and most of their tree-sitter
        // grammar (tree-sitter-cpp reuses tree-sitter-c's node types).
        .target(
            name: "AcaiCFamily",
            dependencies: [
                "AcaiCore",
                "AcaiTreeSitter",
                .product(name: "TreeSitterC", package: "tree-sitter-c"),
                .product(name: "TreeSitterCPP", package: "tree-sitter-cpp"),
            ]
        ),

        // MARK: DOT/Graphviz diagram generator
        .target(
            name: "AcaiDiagram",
            dependencies: ["AcaiCore"]
        ),

        // MARK: Semantic architecture diffing — agnostic graph/metric comparison of two artifacts,
        // plus per-diagram-model (sequence/state/package/call-graph) deltas (depends on AcaiDiagram
        // for those models; still names no language).
        .target(
            name: "AcaiDiff",
            dependencies: ["AcaiCore", "AcaiDiagram"]
        ),

        // MARK: Architecture conformance / fitness functions — agnostic rule evaluation.
        .target(
            name: "AcaiQuality",
            dependencies: ["AcaiCore"]
        ),

        // MARK: Composition root — the only target that names the built-in languages. Wires the
        // parsers + their detectors into `AnalysisService.standard` and re-exports the agnostic API.
        .target(
            name: "AcaiLibrary",
            dependencies: [
                "AcaiCore",
                "AcaiDiagram",
                "AcaiDiff",
                "AcaiQuality",
                "AcaiSwift",
                "AcaiJS",
                "AcaiJVM",
                "AcaiDart",
                "AcaiPython",
                "AcaiCFamily",
            ]
        ),

        // MARK: CLI tool
        .executableTarget(
            name: "AcaiCLI",
            dependencies: [
                "AcaiCore",
                "AcaiDiagram",
                "AcaiDiff",
                "AcaiQuality",
                "AcaiLibrary",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Yams", package: "Yams"),
            ] + cliOptionalDependencies,
        ),

        // MARK: MCP server
        // A third entry point over `AcaiLibrary` (like the CLI and the app): an in-process MCP server
        // exposing the read-only analysis engine as tools over JSON-RPC/stdio. The tool set is
        // deliberately cross-platform (no rendering), so this target builds on Linux too.
        .executableTarget(
            name: "AcaiMCP",
            dependencies: [
                "AcaiCore",
                "AcaiDiagram",
                "AcaiQuality",
                "AcaiLibrary",
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Yams", package: "Yams"),
            ] + mcpOptionalDependencies
        ),

        // MARK: Tests
        .testTarget(name: "AcaiCoreTests", dependencies: ["AcaiCore"]),
        .testTarget(name: "AcaiSwiftTests", dependencies: ["AcaiSwift", "AcaiCore"]),
        .testTarget(name: "AcaiJSTests", dependencies: ["AcaiJS", "AcaiCore"]),
        .testTarget(name: "AcaiJVMTests", dependencies: ["AcaiJVM", "AcaiCore"]),
        .testTarget(name: "AcaiDartTests", dependencies: ["AcaiDart", "AcaiCore"]),
        .testTarget(name: "AcaiPythonTests", dependencies: ["AcaiPython", "AcaiCore"]),
        .testTarget(name: "AcaiCFamilyTests", dependencies: ["AcaiCFamily", "AcaiCore"]),
        .testTarget(name: "AcaiDiagramTests", dependencies: ["AcaiDiagram", "AcaiCore"]),
        .testTarget(name: "AcaiDiffTests", dependencies: ["AcaiDiff", "AcaiCore", "AcaiDiagram"]),
        .testTarget(name: "AcaiQualityTests", dependencies: ["AcaiQuality", "AcaiCore"]),
        .testTarget(name: "AcaiLibraryTests", dependencies: ["AcaiLibrary", "AcaiDiagram"]),
        .testTarget(name: "AcaiCLITests", dependencies: ["AcaiCLI", "AcaiCore"]),
        .testTarget(name: "AcaiMCPTests", dependencies: ["AcaiMCP", "AcaiLibrary", "AcaiCore"]),

        // MARK: Golden-file regression tests for the checked-in Examples/ exports.
        // Cross-platform (no AcaiRender dependency); the PNG checks live in AcaiRenderTests.
        .testTarget(name: "AcaiExamplesTests", dependencies: ["AcaiLibrary", "AcaiDiagram", "AcaiDiff", "AcaiCore"])
    ] + optionalTargets
)
