# ``AcaiTreeSitter``

Shared Tree-sitter helpers the grammar-based parsers are built on. Reach for this only if you're
writing a new parser.

## Overview

Every non-Swift language plugin — [AcaiJS](/documentation/acaijs/),
[AcaiJVM](/documentation/acaijvm/), [AcaiDart](/documentation/acaidart/),
[AcaiPython](/documentation/acaipython/), and [AcaiCFamily](/documentation/acaicfamily/) — is built on
Tree-sitter. `AcaiTreeSitter` collects the plumbing they have in common so each grammar plugin can
focus on its own node mapping instead of re-implementing tree walking, source slicing, and the
recurring call-site / assignment extraction passes. It re-exports `SwiftTreeSitter`.

## The shape a plugin takes

Extraction splits in two, along the line where per-language variation actually lives.

**The algorithms are shared and live here**, each as a value you construct once and keep: the
recursive body walks (``CallSiteResolver``, ``AssignmentResolver``, ``FieldReadResolver``), the
receiver decision tree (``MemberCallResolver``), literal classification (``LiteralClassifier``), the
declared-type pre-pass (``TypeNamePrepass``) and error reporting
(``ParseDiagnosticsCollector``). The declaration bookkeeping is shared too, one level up in
[DeclarationBuilder](/documentation/acaicore/declarationbuilder) and
[MemberIndex](/documentation/acaicore/memberindex) — they name no `Node`, so a SwiftSyntax parser
can use them as well.

**What a language writes** is the narrow adapter each of those algorithms is parameterised by:
``CallSiteSyntax`` (classify one node as a call; recognise one local binding) and
``AssignmentSyntax`` (classify one node as an assignment), plus the small data tables —
``LiteralNodeTypes``, ``MemberCallGrammar``, ``ModifierClassifier``'s keyword lookup, and the
branch-node set for `Node.cyclomaticComplexity(branchKinds:)`.

Because an adapter is a stateless value rather than a protocol the extractor conforms to, a
plugin's own small collaborator types can be handed the same resolvers. `AcaiPython` is the worked
example: `PythonExtractor` owns a `DeclarationBuilder` and one instance of each resolver, and
conforms to nothing.

``TreeSitterExtracting``, ``CallSiteResolving`` and ``AssignmentResolving`` are the previous,
monolithic shape: one type owning every concern and reaching shared code by conforming. They now
only forward to the values above, and exist so the plugins that have not been migrated yet keep
compiling. Don't write a new plugin against them.

## Topics

### Writing a language's adapter

- ``CallSiteSyntax``
- ``AssignmentSyntax``
- ``SourceFileContext``
- ``LiteralNodeTypes``
- ``MemberCallGrammar``

### Shared extraction algorithms

- ``CallSiteResolver``
- ``AssignmentResolver``
- ``FieldReadResolver``
- ``MemberCallResolver``
- ``LiteralClassifier``
- ``TypeNamePrepass``
- ``ParseDiagnosticsCollector``
- ``ModifierClassifier``
- ``CallSiteScope``
- ``ModifierInfo``

### Superseded

- ``TreeSitterExtracting``
- ``CallSiteResolving``
- ``AssignmentResolving``
