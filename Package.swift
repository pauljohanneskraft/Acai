// swift-tools-version: 6.0
// TEMPORARY: pared down to UMLCore + UMLTreeSitter + UMLPython only, to run UMLPythonTests in
// isolation while the other four Tree-sitter plugins are still mid-rewrite (Phase 2). Restored via
// `git checkout -- Package.swift` immediately after.

import PackageDescription

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
        .library(name: "UMLPython", targets: ["UMLPython"]),
    ],
    dependencies: [
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", from: "0.9.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-python", exact: "0.25.0"),
    ],
    targets: [
        .target(name: "UMLCore", dependencies: []),
        .target(
            name: "UMLTreeSitter",
            dependencies: [
                "UMLCore",
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
            ]
        ),
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
        .testTarget(name: "UMLCoreTests", dependencies: ["UMLCore"]),
        .testTarget(name: "UMLPythonTests", dependencies: ["UMLPython", "UMLCore"]),
    ]
)
