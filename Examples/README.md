# Examples

This folder is UML's showroom **and** its proving ground. Every diagram the tool can draw has a small, self-contained sample here — and alongside each sample, the **checked-in DOT, Mermaid, and PNG exports** generated from it. The exports do double duty: they're proof the tool really produces these diagrams, and they're the fixtures the regression tests compare against, in [`Tests/UMLExamplesTests`](../Tests/UMLExamplesTests) (DOT/Mermaid) and [`Tests/UMLRenderTests`](../Tests/UMLRenderTests) (PNG). If a generator drifts, a test goes red.

Each diagram type is modeled **once** and translated into every relevant language using the same type, member, and method names — so a given diagram looks the same no matter which language produced it. The only differences are the ones a language genuinely forces: plain JavaScript has no interfaces or enums, enum-case casing follows each language's convention, and so on.

## Layout

```
Examples/
  ClassDiagram/      Swift Kotlin Java TypeScript Dart Python C Cpp                       + Exports/
  SequenceDiagram/   Swift Kotlin Java TypeScript Dart Python C Cpp                       + Exports/
  StateDiagram/      Swift Kotlin Java TypeScript JavaScript Dart Python C Cpp            + Exports/
  PackageDiagram/    Swift Kotlin Java TypeScript Dart Python C Cpp  (Core/ + Banking/)   + Exports/
  CallGraph/         Swift Kotlin Java TypeScript Dart Python C Cpp                       + Exports/
  ClassDiagramDiff/    Swift Kotlin Java TypeScript Dart Python C Cpp        (Before/+After/) + Exports/
  SequenceDiagramDiff/ Swift Kotlin Java TypeScript Dart Python C Cpp        (Before/+After/) + Exports/
  StateDiagramDiff/    Swift Kotlin Java TypeScript JavaScript Dart Python C Cpp (Bef/+Aft/) + Exports/
  PackageDiagramDiff/  Swift Kotlin Java TypeScript Dart Python C Cpp  (Before/+After/, modules) + Exports/
  CallGraphDiff/       Swift Kotlin Java TypeScript Dart Python C Cpp        (Before/+After/) + Exports/
```

Each `Exports/` holds one `<language>.dot`, one `<language>.mmd` (Mermaid — embeds directly in Markdown), and one `<language>.png` per language. There's deliberately **no** combined all-languages image: the languages reuse the same type names on purpose, so analysing them together would collide identically-named types into one merged graph. The per-language images are the faithful view. This is sample *input*, not a buildable package — no `Package.swift`, no Gradle build.

### Language coverage

Not every language can express every diagram, and where one bows out there's a reason:

| Diagram      | Languages                                   | Why |
| ------------ | ------------------------------------------- | --- |
| **Class**    | Swift, Kotlin, Java, TypeScript, Dart, Python, C, C++ | JavaScript is omitted: with no type annotations its diagram shows only inheritance — see the [`StateDiagram`](StateDiagram) example for JS instead. Python carries types via hints, and its instance attributes come from `self.x = …` in `__init__`. C models the domain with `struct`s + composition; C++ with classes + inheritance. |
| **Sequence** | Swift, Kotlin, Java, TypeScript, Dart, Python, C, C++  | Needs callable receivers. The OO languages enter on a method (`Checkout.placeOrder`); C has no methods, so it enters on the free function `place_order` and renders the same call chain as `<<control>>` lifelines. Only plain JavaScript stays out (no typed call data). |
| **State**    | Swift, Kotlin, Java, TypeScript, JavaScript, Dart, Python, C, C++ | Value-flow analysis only needs assignments, which every parser extracts. C has no methods, so its transitions live in free functions that mutate the struct by pointer (`d->state = …`); the analysis attributes those writes to `Download` by receiver type. (C has no in-struct initializer, so it omits the `idle` initial-only state the others show.) |
| **Package**  | Swift, Kotlin, Java, TypeScript, Dart, Python, C, C++ | Module grouping is path-based (`BuildProduct`); each parser's cross-module relationships are exercised. The same `Core` abstraction counts toward abstractness, so the seven that express it as an abstract type — Swift/Kotlin/Java/TS `protocol`/`interface`, Dart `abstract class`, Python `ABC`, C++ pure-virtual `class` — report `A=0.33`. Only C reports `A=0.00`: its abstraction is a struct of function pointers, a concrete type. |
| **CallGraph**| Swift, Kotlin, Java, TypeScript, Dart, Python, C, C++ | Needs typed call receivers (like Sequence); JavaScript is omitted. C resolves free-function → free-function calls; the rest render the same order-submission graph. |
| **…Diff** (×5) | Each base diagram type's coverage | A `uml diff` between two revisions of one codebase (`Before/` + `After/`), rendered as that diagram type with its added/removed/changed elements **colour-coded — added green, removed red, changed amber, unchanged untinted**. One `*Diff/` tree per diagram type (`ClassDiagramDiff`, `SequenceDiagramDiff`, `StateDiagramDiff`, `PackageDiagramDiff`, `CallGraphDiff`), each mirroring that type's language coverage. **Mermaid caveat:** Mermaid's `sequenceDiagram`/`stateDiagram` syntaxes have no per-edge colour, so those two `.delta.mmd` are the union **uncolored** (the `.delta.dot` carries the colour); class/package/call-graph get colour in both. No PNG — the colours are the point and stay plain-text reviewable in the `.dot`/`.mmd`. |

### The models

Five little domains, each chosen to exercise a different corner of the analysis:

- **ClassDiagram** — a media library. `Playable` (protocol/interface) ← `MediaItem` ← `Song` / `Podcast` (inheritance), `Playlist` composing `[MediaItem]` and `Library` composing `[Playlist]` (composition), `Player` depending on `Library` / `Playable` (dependency), and a `Genre` enum. Every relationship kind in one picture.
- **CallGraph** — an order-submission flow. `OrderController.submit` fans out to `Validator.validate` and `OrderService.place`, which in turn call `PaymentService.charge` and `OrderRepository.save` — a small branching static call graph built from `callSites`.
- **SequenceDiagram** — a checkout flow. `Checkout.placeOrder()` → `PaymentService.charge()` → `PaymentGateway.authorize()`, traced through explicitly-typed properties.
- **StateDiagram** — a `Download` whose `state` advances through a pipeline. `run()` walks the happy path (`requested → downloading → verifying → finished`) as a sequence of assignments, which the value-flow analysis renders as a transition chain, while `fail()` branches off.
- **PackageDiagram** — a two-module banking model. A `Core` module (`Money`, `Account`, and the `AccountRepository` abstraction) and a `Banking` module (`TransferService`, `InMemoryAccountRepository`) that depends on it, yielding a `Banking → Core` edge with the modules' instability/abstractness metrics. Unlike the other examples (one type-name set reused across languages), modules are **directories**, so each language lives in its own tree scanned on its own.
- **…Diff** (five trees) — each proves the **delta** rendering for one diagram type by analysing a `Before/` and an `After/` revision and rendering the union with changed elements tinted. The change is chosen to read naturally in each language (per-language-natural, not one shared model): **ClassDiagramDiff** drops an inheritance and adds a composition in the OO languages, and swaps one composition for another in C (no inheritance); **SequenceDiagramDiff** removes a `verify()` message and adds a `log()` one; **StateDiagramDiff** removes the `verifying` step so its two transitions appear added and the old direct edge removed; **PackageDiagramDiff** adds a new `Reporting` module depending on `Core`; **CallGraphDiff** adds the `OrderService.place → OrderRepository.save` call. `uml diff --diagram` (plus the matching diagram-type flag) renders each.

## Regenerating the exports

Run these from the repository root with the CLI built (`swift build`, then use `.build/debug/UMLCLI`, or install it as `uml` via `./Scripts/cli_install.sh`). Substitute each language the diagram supports (see the coverage table) for `<lang>`.

Every `uml diagram` command also takes `--format mermaid` to write the `.mmd` sibling (same source, entry point, and variable — only the output format and extension change). Every `uml image` command renders the light theme by default; add `--theme dark` and write to the `<lang>.dark.png` sibling to regenerate the dark-palette proof image (e.g. `uml image --source Examples/ClassDiagram --language swift --grouping none --theme dark --output Examples/ClassDiagram/Exports/swift.dark.png --scale 2`).

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

# Delta diagrams — `uml diff` between two revisions, colour-coding added/removed/changed elements.
# <Lang> is the dir name; <lang> the lower-case stem. Each delta has a `.delta.dot`, a `.delta.mmd`
# and a `.delta.png`. One block per diagram type — add the matching diagram-type flag; the class
# form needs none. (Mermaid's sequence/state syntax can't colour edges, so those two `.delta.mmd`
# are the union uncolored; the `.delta.dot` and `.delta.png` carry the colour for every type.)
uml diff --source-old Examples/ClassDiagramDiff/<Lang>/Before \
    --source-new Examples/ClassDiagramDiff/<Lang>/After --language <lang> --diagram dot \
    --output Examples/ClassDiagramDiff/Exports/<lang>.delta.dot   # repeat with --diagram mermaid

uml diff --source-old Examples/SequenceDiagramDiff/<Lang>/Before \
    --source-new Examples/SequenceDiagramDiff/<Lang>/After --language <lang> \
    --sequence-from "Checkout.placeOrder" --diagram dot \
    --output Examples/SequenceDiagramDiff/Exports/<lang>.delta.dot   # C: --sequence-from place_order

uml diff --source-old Examples/StateDiagramDiff/<Lang>/Before \
    --source-new Examples/StateDiagramDiff/<Lang>/After --language <lang> \
    --state-from "Download.state" --diagram dot \
    --output Examples/StateDiagramDiff/Exports/<lang>.delta.dot

uml diff --source-old Examples/PackageDiagramDiff/<Lang>/Before \
    --source-new Examples/PackageDiagramDiff/<Lang>/After --language <lang> --package --diagram dot \
    --output Examples/PackageDiagramDiff/Exports/<lang>.delta.dot

uml diff --source-old Examples/CallGraphDiff/<Lang>/Before \
    --source-new Examples/CallGraphDiff/<Lang>/After --language <lang> --call-graph --diagram dot \
    --output Examples/CallGraphDiff/Exports/<lang>.delta.dot

# Delta PNGs (macOS only) — `uml image` with --source-old renders the union with the same colour
# coding, natively (matching the other example PNGs). Add the matching diagram-type flag per type.
uml image --source-old Examples/ClassDiagramDiff/<Lang>/Before \
    --source Examples/ClassDiagramDiff/<Lang>/After --language <lang> --grouping none \
    --output Examples/ClassDiagramDiff/Exports/<lang>.delta.png --scale 2
uml image --source-old Examples/SequenceDiagramDiff/<Lang>/Before \
    --source Examples/SequenceDiagramDiff/<Lang>/After --language <lang> \
    --sequence-from "Checkout.placeOrder" \
    --output Examples/SequenceDiagramDiff/Exports/<lang>.delta.png --scale 2   # C: --sequence-from place_order
uml image --source-old Examples/StateDiagramDiff/<Lang>/Before \
    --source Examples/StateDiagramDiff/<Lang>/After --language <lang> --state-from "Download.state" \
    --output Examples/StateDiagramDiff/Exports/<lang>.delta.png --scale 2
uml image --source-old Examples/PackageDiagramDiff/<Lang>/Before \
    --source Examples/PackageDiagramDiff/<Lang>/After --language <lang> --package \
    --output Examples/PackageDiagramDiff/Exports/<lang>.delta.png --scale 2
uml image --source-old Examples/CallGraphDiff/<Lang>/Before \
    --source Examples/CallGraphDiff/<Lang>/After --language <lang> --call-graph \
    --output Examples/CallGraphDiff/Exports/<lang>.delta.png --scale 2
```

> `uml image` is macOS-only — it renders with SwiftUI's `ImageRenderer`, which needs a window-server session. On Linux, use `uml diagram … | dot -Tpng` to produce images via Graphviz instead.

The PNGs live in **Git LFS** (see [`.gitattributes`](../.gitattributes)); the `.dot` and `.mmd` files are plain text so they stay reviewable in diffs. If you change the samples or the generators, regenerate the affected exports and re-run `swift test` — the regression tests compare freshly-generated DOT **and Mermaid** byte-for-byte and re-render each PNG to confirm it still matches.
