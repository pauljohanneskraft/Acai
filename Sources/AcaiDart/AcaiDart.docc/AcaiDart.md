# ``AcaiDart``

The Dart plugin — parses `.dart` source into the [AcaiCore](/documentation/acaicore/) model with
Tree-sitter.

## Overview

`AcaiDart` is a self-contained language plugin built on Tree-sitter (shared helpers come from
[AcaiTreeSitter](/documentation/acaitreesitter/)). The ``DartCodeParser`` reports
`SourceLanguage.dart` and carries Dart's
[LanguageConfiguration](/documentation/acaicore/languageconfiguration); the ``FlutterDetector``
finds source in Flutter/Dart projects via `pubspec.yaml`.

Dart's `abstract class` maps onto the model's abstract type, so it participates fully in
inheritance, composition, and package-abstractness analysis.

## Topics

### Parsing

- ``DartCodeParser``

### Project discovery

- ``FlutterDetector``
