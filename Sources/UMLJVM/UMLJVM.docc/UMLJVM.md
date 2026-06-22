# ``UMLJVM``

The JVM plugin — parses both **Java** (`.java`) and **Kotlin** (`.kt`, `.kts`) into the
[UMLCore](/documentation/umlcore/) model with Tree-sitter.

## Overview

Java and Kotlin share a single plugin because they share the JVM build systems (Gradle, Maven).
`UMLJVM` ships two stateless parsers — ``JavaCodeParser`` and ``KotlinCodeParser`` — each reporting
its own `SourceLanguage` (`java` / `kotlin`) and carrying its own
[LanguageConfiguration](/documentation/umlcore/languageconfiguration), plus a shared
``JVMBuildSystemDetector`` that locates source roots in Gradle and Maven projects.

Both parsers are Tree-sitter based (shared helpers come from
[UMLTreeSitter](/documentation/umltreesitter/)) and emit the same model, so a mixed Java/Kotlin
codebase merges into one diagram.

## Topics

### Parsing

- ``JavaCodeParser``
- ``KotlinCodeParser``

### Project discovery

- ``JVMBuildSystemDetector``
