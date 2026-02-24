// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "UML",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "UMLCore",       targets: ["UMLCore"]),
        .library(name: "UMLTreeSitter", targets: ["UMLTreeSitter"]),
        .library(name: "UMLSwift",      targets: ["UMLSwift"]),
        .library(name: "UMLKotlin",     targets: ["UMLKotlin"]),
        .library(name: "UMLJS",         targets: ["UMLJS"]),
        .library(name: "UMLJava",       targets: ["UMLJava"]),
        .library(name: "UMLDiagram",    targets: ["UMLDiagram"]),
        .library(name: "UMLLibrary",    targets: ["UMLLibrary"]),
        .executable(name: "uml",        targets: ["UMLCLI"]),
        .executable(name: "UMLApp",     targets: ["UMLApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git",            from: "600.0.0"),
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter",         from: "0.9.0"),
        .package(url: "https://github.com/fwcd/tree-sitter-kotlin",               from: "0.3.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-typescript",    from: "0.21.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-java",          from: "0.21.0"),
        .package(url: "https://github.com/apple/swift-argument-parser",           from: "1.3.0"),
        .package(url: "https://github.com/jpsim/Yams",                            from: "5.0.0"),
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
                "UMLDiagram",
            ]
        ),
        
        // MARK: App
        .executableTarget(
            name: "UMLApp",
            dependencies: [
                "UMLCore",
                "UMLTreeSitter",
                "UMLSwift",
                "UMLKotlin",
                "UMLJS",
                "UMLJava",
                "UMLDiagram",
                "UMLLibrary",
            ],
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
                "UMLDiagram",
                "UMLLibrary",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Yams", package: "Yams"),
            ],
        ),

        // MARK: Tests
        .testTarget(name: "UMLCoreTests",    dependencies: ["UMLCore"]),
        .testTarget(name: "UMLSwiftTests",   dependencies: ["UMLSwift",   "UMLCore"]),
        .testTarget(name: "UMLKotlinTests",  dependencies: ["UMLKotlin",  "UMLCore"]),
        .testTarget(name: "UMLJSTests",      dependencies: ["UMLJS",      "UMLCore"]),
        .testTarget(name: "UMLJavaTests",    dependencies: ["UMLJava",    "UMLCore"]),
        .testTarget(name: "UMLDiagramTests", dependencies: ["UMLDiagram", "UMLCore"]),
        .testTarget(name: "UMLLibraryTests", dependencies: ["UMLLibrary"])
    ]
)
