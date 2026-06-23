# ``UMLCore``

The language-agnostic engine: the data model every parser produces, and the abstractions that turn a folder of source into it.

## Overview

`UMLCore` is the vocabulary the rest of UML speaks. A parser reads source text and emits a
``CodeArtifact`` — a unified model of the types, members, and relationships it found — and every
other module (diagram generation, rendering, the CLI, the app) consumes that one model. Nothing in
this module knows about a *specific* language: a language's quirks live in its own plugin and reach
the engine only through ``LanguageConfiguration``, resolved from the ``LanguageRegistry``.

If you're building on UML, this is the module to understand first — it's the shape of the data.
For the practical "analyze a folder and draw it" path, jump to
[Getting Started](/documentation/umllibrary/gettingstarted) over in [UMLLibrary](/documentation/umllibrary/).

### The model in one breath

``AnalysisService`` discovers the source directories in a project, runs the right ``CodeParser``
for each file, and merges the results into a single ``CodeArtifact``. That artifact holds
``TypeDeclaration``s (each with its ``Member``s, ``AccessLevel``, ``TypeKind``, and ``Modifier``s)
and the ``Relationship``s between them. Call-graph and value-flow data (``CallSite``,
``VariableAssignment``) ride along so the diagram layer can derive sequence, state, and call-graph
views without re-parsing.

### Writing a new parser

A language is a self-contained plugin. It provides a ``CodeParser`` (which owns its file
extensions and a ``CodeParser/parse(source:fileName:)``), a ``CodeArtifact/SourceLanguage`` constant
defined as an extension (there are **no** built-in language constants here — agnostic by design), a
``LanguageConfiguration`` describing the language's primitives, collections, stereotypes, and
generated-code filter, and one or more build-system detectors. See the `/add-language` workflow and
the existing plugins for a template.

## Topics

### The parsed model

- ``CodeArtifact``
- ``TypeDeclaration``
- ``Member``
- ``Relationship``
- ``EnumCase``
- ``AccessLevel``
- ``TypeKind``
- ``Modifier``
- ``CodeArtifact/SourceLanguage``
- ``SourceLocation``

### Analysis & metrics

- ``CallSite``
- ``VariableAssignment``
- ``CodeMetrics``
- ``FocusConfiguration``

### Parser abstractions

- ``CodeParser``
- ``LanguageConfiguration``
- ``LanguageRegistry``
- ``GeneratedCodeFilter``
- ``NamePattern``

### Project discovery

How ``AnalysisService`` finds the source folders inside a project before parsing. You don't
usually touch these directly — they power the automatic discovery.

- ``AnalysisService``
- ``ProjectDiscovery``
- ``BuildSystemDetector``
- ``ModuleResolver``
- ``FallbackDetector``
- ``SourceSpec``

### Diagnostics & constants

- ``ParseDiagnostic``
- ``UMLConstants``
