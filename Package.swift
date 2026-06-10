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
            "UMLLibrary",
        ]
    )
)
optionalTargets.append(
    .testTarget(name: "UMLRenderTests", dependencies: ["UMLRender", "UMLCore", "UMLLibrary"])
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
            "UMLTreeSitter",
            "UMLSwift",
            "UMLKotlin",
            "UMLJS",
            "UMLJava",
            "UMLDart",
            "UMLDiagram",
            "UMLLibrary",
            "UMLRender",
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
        .library(name: "UMLKotlin", targets: ["UMLKotlin"]),
        .library(name: "UMLJS", targets: ["UMLJS"]),
        .library(name: "UMLJava", targets: ["UMLJava"]),
        .library(name: "UMLDart", targets: ["UMLDart"]),
        .library(name: "UMLDiagram", targets: ["UMLDiagram"]),
        .library(name: "UMLLibrary", targets: ["UMLLibrary"]),
    ] + optionalProducts,
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", from: "0.9.0"),
        .package(url: "https://github.com/fwcd/tree-sitter-kotlin", from: "0.3.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-typescript", from: "0.21.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-java", from: "0.21.0"),
        .package(url: "https://github.com/UserNobody14/tree-sitter-dart", branch: "master"),
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
            ]
        ),
        .target(
            name: "UMLKotlin",
            dependencies: [
                "UMLCore",
                "UMLTreeSitter",
                .product(name: "TreeSitterKotlin", package: "tree-sitter-kotlin"),
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
        .target(
            name: "UMLJava",
            dependencies: [
                "UMLCore",
                "UMLTreeSitter",
                .product(name: "TreeSitterJava", package: "tree-sitter-java"),
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

        // MARK: DOT/Graphviz diagram generator
        .target(
            name: "UMLDiagram",
            dependencies: ["UMLCore"]
        ),

        // MARK: UML Library
        .target(
            name: "UMLLibrary",
            dependencies: [
                "UMLCore",
                "UMLTreeSitter",
                "UMLSwift",
                "UMLKotlin",
                "UMLJS",
                "UMLJava",
                "UMLDart",
                "UMLDiagram",
            ]
        ),

        // MARK: CLI tool
        .executableTarget(
            name: "UMLCLI",
            dependencies: [
                "UMLCore",
                "UMLTreeSitter",
                "UMLSwift",
                "UMLKotlin",
                "UMLJS",
                "UMLJava",
                "UMLDart",
                "UMLDiagram",
                "UMLLibrary",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Yams", package: "Yams"),
            ] + cliOptionalDependencies,
        ),

        // MARK: Tests
        .testTarget(name: "UMLCoreTests", dependencies: ["UMLCore"]),
        .testTarget(name: "UMLSwiftTests", dependencies: ["UMLSwift", "UMLCore"]),
        .testTarget(name: "UMLKotlinTests", dependencies: ["UMLKotlin", "UMLCore"]),
        .testTarget(name: "UMLJSTests", dependencies: ["UMLJS", "UMLCore"]),
        .testTarget(name: "UMLJavaTests", dependencies: ["UMLJava", "UMLCore"]),
        .testTarget(name: "UMLDartTests", dependencies: ["UMLDart", "UMLCore"]),
        .testTarget(name: "UMLDiagramTests", dependencies: ["UMLDiagram", "UMLCore"]),
        .testTarget(name: "UMLLibraryTests", dependencies: ["UMLLibrary"])
    ] + optionalTargets
)
