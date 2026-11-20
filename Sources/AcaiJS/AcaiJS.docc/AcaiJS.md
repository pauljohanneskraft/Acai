# ``AcaiJS``

The JavaScript / TypeScript plugin — parses `.ts`/`.mts`/`.cts`/`.tsx` and
`.js`/`.jsx`/`.mjs`/`.cjs` into the [AcaiCore](/documentation/acaicore/) model with Tree-sitter.

## Overview

`AcaiJS` is a self-contained language plugin built on Tree-sitter (shared helpers come from
[AcaiTreeSitter](/documentation/acaitreesitter/)). The ``JSCodeParser`` reports either
`SourceLanguage.typeScript` or `SourceLanguage.javaScript` depending on the file, and the
``NodeDetector`` finds source via `package.json`. The grammar is chosen by extension: `.ts`,
`.mts` and `.cts` take the TypeScript grammar, while `.tsx` and every JavaScript extension take
TSX, which adds JSX at no cost to JavaScript — it has no `<T>x` cast for elements to clash with.

> **JavaScript is intentionally thin.** Plain JS has no type annotations, so a JS-only diagram
> shows little beyond inheritance. TypeScript carries interfaces, enums, and typed members, so it
> produces the full picture — reach for `.ts` when you want detail.

## Topics

### Parsing

- ``JSCodeParser``

### Project discovery

- ``NodeDetector``
