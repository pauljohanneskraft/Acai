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

If you're *using* Açaí you'll never import this directly. If you're *adding a Tree-sitter language*,
``SourceFileContext`` and the ``TreeSitterExtracting`` / ``CallSiteResolving`` /
``AssignmentResolving`` helpers are your starting point.

## Topics

### Building a Tree-sitter parser

- ``SourceFileContext``
- ``TreeSitterExtracting``
- ``CallSiteResolving``
- ``AssignmentResolving``
- ``CallSiteScope``
- ``ModifierInfo``
