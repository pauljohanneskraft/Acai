# Examples

Small, self-contained sample code that exercises every diagram UML can draw, plus the
**checked-in DOT and PNG exports** generated from it. The exports double as proof that the
tool really produces these diagrams and as fixtures for the regression tests in
[`Tests/UMLExamplesTests`](../Tests/UMLExamplesTests) (DOT) and
[`Tests/UMLRenderTests`](../Tests/UMLRenderTests) (PNG).

Each diagram type uses **one shared model, translated into every relevant language with the
same type, member, and method names** — so a given diagram looks the same no matter which
language produced it (allowing for what a language can't express: plain JavaScript has no
interfaces or enums, enum-case casing follows each language's convention, etc.).

## Layout

```
Examples/
  ClassDiagram/      Swift Kotlin Java TypeScript Dart Python C Cpp        + Exports/
  SequenceDiagram/   Swift Kotlin Java TypeScript Dart Python C Cpp        + Exports/
  StateDiagram/      Swift Kotlin Java TypeScript JavaScript Dart Python C Cpp   + Exports/
  PackageDiagram/    Swift Kotlin Java TypeScript Dart Python C Cpp  (Core/ + Banking/ modules)  + Exports/
  CallGraph/         Swift Kotlin Java TypeScript Dart Python C Cpp                            + Exports/
```

Each `Exports/` holds one `<language>.dot`, one `<language>.mmd` (Mermaid — embeds directly in
Markdown), and one `<language>.png` per language. (There's no
combined all-languages image: the languages reuse the same type names on purpose, so analysing
them together would collide identically-named types into one merged graph — the per-language
images are the faithful view.) This is sample input, not a buildable package — there's no
`Package.swift` or Gradle build.

### Language coverage

| Diagram      | Languages                                   | Why |
| ------------ | ------------------------------------------- | --- |
| **Class**    | Swift, Kotlin, Java, TypeScript, Dart, Python, C, C++ | JavaScript is omitted: with no type annotations its diagram shows only inheritance — see the [`StateDiagram`](StateDiagram) example for JS instead. Python carries types via hints, and its instance attributes come from `self.x = …` in `__init__`. C models the domain with `struct`s + composition; C++ with classes + inheritance. |
| **Sequence** | Swift, Kotlin, Java, TypeScript, Dart, Python, C, C++  | Needs callable receivers. The OO languages enter on a method (`Checkout.placeOrder`); C has no methods, so it enters on the free function `place_order` and renders the same call chain as `<<control>>` lifelines. Only plain JavaScript stays out (no typed call data). |
| **State**    | Swift, Kotlin, Java, TypeScript, JavaScript, Dart, Python, C, C++ | Value-flow analysis only needs assignments, which every parser extracts. C has no methods, so its transitions live in free functions that mutate the struct by pointer (`d->state = …`); the analysis attributes those writes to `Download` by receiver type. (C has no in-struct initializer, so it omits the `idle` initial-only state the others show.) |
| **Package**  | Swift, Kotlin, Java, TypeScript, Dart, Python, C, C++ | Module grouping is path-based (`BuildProduct`); each parser's cross-module relationships are exercised. The same `Core` abstraction counts toward abstractness, so the seven that express it as an abstract type — Swift/Kotlin/Java/TS `protocol`/`interface`, Dart `abstract class`, Python `ABC`, C++ pure-virtual `class` — report `A=0.33`. Only C reports `A=0.00`: its abstraction is a struct of function pointers, a concrete type. |
| **CallGraph**| Swift, Kotlin, Java, TypeScript, Dart, Python, C, C++ | Needs typed call receivers (like Sequence); JavaScript is omitted. C resolves free-function → free-function calls; the rest render the same order-submission graph. |

### The models

- **ClassDiagram** — a media library: `Playable` (protocol/interface) ← `MediaItem` ←
  `Song` / `Podcast` (inheritance), `Playlist` composing `[MediaItem]` and `Library`
  composing `[Playlist]` (composition), `Player` depending on `Library` / `Playable`
  (dependency), and a `Genre` enum.
- **CallGraph** — an order-submission flow: `OrderController.submit` fans out to
  `Validator.validate` and `OrderService.place`, which in turn calls `PaymentService.charge`
  and `OrderRepository.save` — a small branching static call graph built from `callSites`.
- **SequenceDiagram** — a checkout flow: `Checkout.placeOrder()` → `PaymentService.charge()`
  → `PaymentGateway.authorize()`, traced through explicitly-typed properties.
- **StateDiagram** — a `Download` whose `state` advances through a pipeline: `run()` walks the
  happy path (`requested → downloading → verifying → finished`) as a sequence of assignments,
  which the value-flow analysis renders as a transition chain, while `fail()` branches off.
- **PackageDiagram** — a two-module banking model: a `Core` module (`Money`, `Account`, and the
  `AccountRepository` abstraction) and a `Banking` module (`TransferService`,
  `InMemoryAccountRepository`) that depends on it, yielding a `Banking → Core` edge with the
  modules' instability/abstractness metrics. Unlike the other examples (one type-name set reused
  across languages), modules are **directories**, so each language lives in its own tree scanned
  on its own.

## Regenerating the exports

From the repository root, with the CLI built (`swift build`, then use `.build/debug/UMLCLI`,
or install it as `uml` via `./Scripts/cli_install.sh`). Substitute each language the diagram
supports (see the coverage table above) for `<lang>`:

Each `uml diagram` command also takes `--format mermaid` to write the `.mmd` sibling (same source,
entry point, and variable — only the output format and extension change).

Each `uml image` command renders the light theme by default; add `--theme dark` and write to the
`<lang>.dark.png` sibling to regenerate the dark-palette proof image (e.g.
`uml image --source Examples/ClassDiagram --language swift --grouping none --theme dark
--output Examples/ClassDiagram/Exports/swift.dark.png --scale 2`).

```sh
# Class diagram — DOT + Mermaid + PNG per language (swift kotlin java typescript dart python c cpp), macOS only for images
uml diagram --source Examples/ClassDiagram --language <lang> \
    --output Examples/ClassDiagram/Exports/<lang>.dot
uml diagram --source Examples/ClassDiagram --language <lang> --format mermaid \
    --output Examples/ClassDiagram/Exports/<lang>.mmd
uml image   --source Examples/ClassDiagram --language <lang> --grouping none \
    --output Examples/ClassDiagram/Exports/<lang>.png --scale 2

# Sequence diagram (swift | kotlin | java | typescript | dart | python | cpp). The entry point is
# "Checkout.placeOrder" for every language EXCEPT c, whose entry is the dotless free function
# "place_order" (substitute it below when --language c).
uml diagram --source Examples/SequenceDiagram --language <lang> \
    --sequence-from "Checkout.placeOrder" \
    --output Examples/SequenceDiagram/Exports/<lang>.dot
uml diagram --source Examples/SequenceDiagram --language <lang> --format mermaid \
    --sequence-from "Checkout.placeOrder" \
    --output Examples/SequenceDiagram/Exports/<lang>.mmd
uml image   --source Examples/SequenceDiagram --language <lang> \
    --sequence-from "Checkout.placeOrder" \
    --output Examples/SequenceDiagram/Exports/<lang>.png --scale 2

# State diagram — uniform variable
uml diagram --source Examples/StateDiagram --language <lang> \
    --state-from "Download.state" \
    --output Examples/StateDiagram/Exports/<lang>.dot
uml diagram --source Examples/StateDiagram --language <lang> --format mermaid \
    --state-from "Download.state" \
    --output Examples/StateDiagram/Exports/<lang>.mmd
uml image   --source Examples/StateDiagram --language <lang> \
    --state-from "Download.state" \
    --output Examples/StateDiagram/Exports/<lang>.png --scale 2

# Package diagram (swift kotlin java typescript dart python c cpp) — scanned per-language SUBDIR so the
# Core/Banking directories become modules. <Lang> is the dir name (Swift, Kotlin, Java,
# TypeScript, Dart, Python, C, Cpp); <lang> the lower-case stem (note: TypeScript dir vs typescript
# stem, and Cpp dir vs cpp stem).
uml diagram --source Examples/PackageDiagram/<Lang> --language <lang> --package \
    --output Examples/PackageDiagram/Exports/<lang>.dot
uml diagram --source Examples/PackageDiagram/<Lang> --language <lang> --package --format mermaid \
    --output Examples/PackageDiagram/Exports/<lang>.mmd
uml image   --source Examples/PackageDiagram/<Lang> --language <lang> --package \
    --output Examples/PackageDiagram/Exports/<lang>.png --scale 2

# Call graph (swift kotlin java typescript dart python c cpp) — whole-codebase scope.
uml diagram --source Examples/CallGraph/<Lang> --language <lang> --call-graph \
    --output Examples/CallGraph/Exports/<lang>.dot
uml diagram --source Examples/CallGraph/<Lang> --language <lang> --call-graph --format mermaid \
    --output Examples/CallGraph/Exports/<lang>.mmd
uml image   --source Examples/CallGraph/<Lang> --language <lang> --call-graph \
    --output Examples/CallGraph/Exports/<lang>.png --scale 2
```

> `uml image` is macOS-only — it renders with SwiftUI's `ImageRenderer`, which needs a
> window-server session. On Linux, use `uml diagram … | dot -Tpng` to produce images via
> Graphviz instead.

The PNGs are stored in **Git LFS** (see [`.gitattributes`](../.gitattributes)); the `.dot` and
`.mmd` files are plain text so they stay reviewable in diffs. If you change the samples or the
generators, regenerate the affected exports and re-run `swift test` — the regression tests compare
freshly-generated DOT **and Mermaid** byte-for-byte and re-render each PNG to confirm it still matches.
