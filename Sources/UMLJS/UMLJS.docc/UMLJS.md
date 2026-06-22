# ``UMLJS``

The JavaScript / TypeScript plugin — parses `.ts`/`.tsx` and `.js`/`.jsx`/`.mjs` into the
[UMLCore](/documentation/umlcore/) model with Tree-sitter.

## Overview

`UMLJS` is a self-contained language plugin built on Tree-sitter (shared helpers come from
[UMLTreeSitter](/documentation/umltreesitter/)). The ``JSCodeParser`` reports either
`SourceLanguage.typeScript` or `SourceLanguage.javaScript` depending on the file, and the
``NodeDetector`` finds source via `package.json`.

> **JavaScript is intentionally thin.** Plain JS has no type annotations, so a JS-only diagram
> shows little beyond inheritance. TypeScript carries interfaces, enums, and typed members, so it
> produces the full picture — reach for `.ts` when you want detail.

## Topics

### Parsing

- ``JSCodeParser``

### Project discovery

- ``NodeDetector``
