# ``UMLRust``

The Rust plugin — parses `.rs` source into the [UMLCore](/documentation/umlcore/) model with
Tree-sitter.

## Overview

`UMLRust` is a self-contained language plugin built on Tree-sitter (shared helpers come from
[UMLTreeSitter](/documentation/umltreesitter/)). The ``RustCodeParser`` reports
`SourceLanguage.rust` and carries Rust's
[LanguageConfiguration](/documentation/umlcore/languageconfiguration); the ``CargoDetector``
finds source via `Cargo.toml`.

The parser models Rust structs, enums, traits, type aliases, modules, `impl` blocks, method call
sites, and enum-state assignments, so Rust participates in the same class, sequence, call-graph,
state, and package diagrams as the other built-in languages.

## Topics

### Parsing

- ``RustCodeParser``

### Project discovery

- ``CargoDetector``
