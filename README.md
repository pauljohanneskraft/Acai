# UML — Code Diagramming for Your Codebases

UML is a multi-language code analysis and diagramming toolkit. Point it at a codebase and it will parse your source (Swift, Kotlin, Java, TypeScript/JavaScript, and Dart), build a unified model of types and relationships, and generate UML-style diagrams (DOT/Graphviz). You can explore results in a macOS app or automate workflows with a CLI.

## What you can do
- Generate UML diagrams from real code across multiple languages
- Explore your project visually with the macOS app
- Filter and tweak what appears in diagrams (properties, methods, enum cases, access levels, etc.)
- Script and CI friendly via the `uml` command-line tool

---

## Components

- **macOS App (UML.app)**
  - A SwiftUI app for browsing and exporting diagrams.
  - Open a project folder, analyze sources, fine-tune what you see, and export DOT.

- **CLI (`uml`)**
  - A fast command-line tool for analysis and diagram generation.
  - Perfect for automation, CI pipelines, and headless environments.
  - Run `uml --help` for available commands and options.

- **Libraries**
  - A set of Swift packages that parse languages and compose results:
    - Core models and utilities
    - Language parsers (Swift, Kotlin, Java, TypeScript/JavaScript, Dart)
    - Diagram generation helpers (DOT/Graphviz)

---

## Supported languages
- Swift (via SwiftSyntax)
- Kotlin (via Tree-sitter)
- Java (via Tree-sitter)
- TypeScript / JavaScript (via Tree-sitter)
- Dart (via Tree-sitter)

---

## Quick start

### Requirements
- Swift 6 toolchain
- macOS 15+ for the app (the libraries/CLI support broader Apple platforms)
- Optional: Graphviz (`dot`) if you want to render DOT into images

### Build
```sh
swift build
```

### Test
```sh
swift test
```

### App
```sh
./Scripts/app_create.sh # Creates `UML.app` in `.build/artifacts`
./Scripts/app_install.sh # Moves built artifact to `/Applications/UML.app`
./Scripts/app_uninstall.sh # Deletes `/Applications/UML.app`
```

### CLI
```sh
./Scripts/cli_create.sh # Creates `uml` binary in `.build/artifacts`
./Scripts/cli_install.sh # Moves built artifact to binary directory
./Scripts/cli_uninstall.sh # Deletes binary artifact from the respective binary directories
```
