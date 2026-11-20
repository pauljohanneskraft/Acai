# ``AcaiCore``

The language-agnostic engine: the data model every parser produces, and the abstractions that turn a folder of source into it.

## Overview

`AcaiCore` is the vocabulary the rest of Açaí speaks. A parser reads source text and emits a
``CodeArtifact`` — a unified model of the types, members, and relationships it found — and every
other module (diagram generation, rendering, the CLI, the app) consumes that one model. Nothing in
this module knows about a *specific* language: a language's quirks live in its own plugin and reach
the engine only through ``LanguageConfiguration``, resolved from the ``LanguageRegistry``.

If you're building on Açaí, this is the module to understand first — it's the shape of the data.
For the practical "analyze a folder and draw it" path, jump to
[Getting Started](/documentation/guides/gettingstarted) over in [the package overview](/documentation/guides).

### The model in one breath

``AnalysisService`` discovers the source directories in a project, runs the right ``CodeParser``
for each file, and merges the results into a single ``CodeArtifact``. That artifact holds
``TypeDeclaration``s (each with its ``Member``s, ``AccessLevel``, ``TypeKind``, and ``Modifier``s)
and the ``Relationship``s between them. Call-graph and value-flow data (``CallSite``,
``VariableAssignment``) ride along so the diagram layer can derive sequence, state, and call-graph
views without re-parsing.

### Code-smell metrics

``CodeArtifact/computeMetrics()`` folds the parsed model into ``CodeMetrics`` — concept counts,
per-module coupling (Martin's Ca/Ce/I/A/D) and per-type OO metrics (DIT/NOC/WMC/fan-in/out). It also
surfaces a family of *code-smell* metrics computed purely from data the parser already captured, with
no thresholds and no language configuration (raw values only — judgement is left to the reader):

- **Response For a Class** (``CodeMetrics/TypeMetric/responseForClass``) — declared methods plus the
  distinct methods the type calls.
- **Public API surface** (``CodeMetrics/TypeMetric/publicMemberCount`` /
  ``CodeMetrics/TypeMetric/publicMemberRatio``, and ``CodeMetrics/ModuleCoupling/publicMemberCount``)
  — public/open members, per type and per module.
- **Mutable public state** (``CodeMetrics/TypeMetric/mutablePublicState``) — publicly settable stored
  properties, which break encapsulation.
- **Parameter pressure** (``CodeMetrics/TypeMetric/maxParameters`` /
  ``CodeMetrics/TypeMetric/meanParameters``) — the widest and mean parameter list across a type's
  callable members (the long-parameter-list smell).
- **Data-class score** (``CodeMetrics/TypeMetric/dataClassScore``) — the share of a type that is data
  rather than behaviour, `properties / (properties + methods)`; a high score marks an anemic model.
- **Nesting burden** (``CodeMetrics/TypeMetric/nestingDepth``) — the depth of a type's nested-type tree.
- **Inheritance shape** (``CodeMetrics/TypeMetric/overrideCount`` and the derived
  ``CodeMetrics/TypeMetric/deepAndWide``, `DIT × NOC`) — refused-bequest and fragile-hierarchy-hub
  signals.
- **Cohesion** (``CodeMetrics/TypeMetric/lackOfCohesion``, see ``LcomAnalysis``) — an LCOM4-style count
  of the connected components among the members carrying a type's instance behaviour (1 = cohesive;
  higher = several unrelated jobs).
- **Feature envy** (``CodeMetrics/TypeMetric/featureEnvyMethods``, see `FeatureEnvy`) — methods more
  interested in another declared type than their own.

``CodeMetrics/TypeMetric/weightedMethods`` is the textbook WMC: the sum of
``Member/cyclomaticComplexity`` over the type's methods and initialisers, counting a member the parser
measured no body for as 1. ``CodeMetrics/TypeMetric/numberOfMethods`` keeps the plain count beside it,
and is what ``CodeMetrics/TypeMetric/responseForClass`` starts from.

``CodeMetrics/TypeMetric/lackOfCohesion`` links members by shared property access — reads
(``Member/fieldReads``) and writes (``Member/assignments``) — plus self-dispatched calls. It measures
methods, computed properties and subscripts, since each is code reaching into the type's fields;
`static`/`class` members cannot touch instance state and initialisers populate every field, so both
would distort the count and are excluded.

**Known limitation:** ``SourceLocation`` records only a start line, so true method *length* is not
derivable — ``CodeMetrics/TypeMetric/linesOfCode`` measures a declaration's span, not a single member's.

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
- ``ModuleMap``
- ``ProjectRoots``
- ``FallbackDetector``
- ``SourceSpec``

### Diagnostics & constants

- ``ParseDiagnostic``
- ``AcaiConstants``
