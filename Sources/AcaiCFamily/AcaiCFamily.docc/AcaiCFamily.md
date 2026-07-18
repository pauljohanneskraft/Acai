# ``AcaiCFamily``

The C-family plugin — parses both **C** (`.c`, `.h`) and **C++** (`.cpp`, `.hpp`, `.cc`, …) into the
[AcaiCore](/documentation/acaicore/) model with Tree-sitter.

## Overview

C and C++ share a single plugin because they share the C/C++ build systems and most of the grammar.
`AcaiCFamily` ships two stateless parsers — ``CCodeParser`` and ``CppCodeParser`` — each reporting
its own `SourceLanguage` (`c` / `cpp`), plus a shared ``CFamilyBuildSystemDetector``.

There's one subtlety: **C and C++ both claim the `.h` extension.** ``CCodeParser`` owns `.h` and
content-sniffs each header, routing C++ headers (classes, templates, namespaces) to the C++ grammar
and leaving plain-C headers on the C grammar — so a mixed codebase classifies each header correctly.

> **C is modeled with `struct`s.** C has no classes, so its domain shows up as structs plus
> composition, and method-receiver analysis maps free functions back to the type they mutate by
> pointer (`d->state = …`). It's faithful, but it reads differently from the OO languages — C's
> abstractions are concrete structs (e.g. a struct of function pointers), so they don't count toward
> abstractness the way a C++ pure-virtual class does.

## Topics

### Parsing

- ``CCodeParser``
- ``CppCodeParser``

### Project discovery

- ``CFamilyBuildSystemDetector``
