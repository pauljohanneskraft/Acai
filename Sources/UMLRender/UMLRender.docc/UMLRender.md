# ``UMLRender``

Lay out and render a diagram straight to a **PNG** — no Graphviz required. Apple platforms only.

## Overview

`UMLRender` is the visual half of UML. It owns the SwiftUI diagram views, a Sugiyama-style
hierarchical **layout engine**, and the image renderer that turns either into a PNG. It's shared by
two front ends: the macOS app's canvas (drag, resize, group) and the `uml image` CLI command — so
a headless export matches what you'd see on screen, because it runs the same layout and the same
views.

> **Apple platforms only.** Rendering goes through SwiftUI's `ImageRenderer`, which needs a
> window-server session. On Linux, generate DOT with [UMLDiagram](/documentation/umldiagram/) and
> render it with Graphviz (`dot -Tpng`) instead.

### The pieces

- **``DiagramImageRenderer``** — the entry point: give it a diagram (class, sequence, state,
  package, or call graph) and get back PNG `Data`. Throws ``DiagramImageRenderError`` if rendering
  fails.
- **Layout models** — ``DiagramLayoutModel`` (class diagrams, with grouping boxes),
  ``SequenceLayoutModel``, ``CallGraphLayoutModel``, and ``PackageLayoutModel`` compute node frames
  and edge routes independently of any view, so the app and the CLI share one source of geometry.
- **Snapshot views** — ``DiagramSnapshotView``, ``SequenceDiagramSnapshotView``,
  ``PackageDiagramSnapshotView``, and ``CallGraphSnapshotView`` draw a fully-laid-out diagram into
  a static SwiftUI view that `ImageRenderer` can rasterise.
- **Styling** — ``ClassDiagramConfiguration`` and ``DiagramPalette`` control grouping, theme, and
  colours.

## Topics

### Rendering to an image

- ``DiagramImageRenderer``
- ``DiagramImageRenderError``

### Layout engine

- ``DiagramLayoutModel``
- ``SequenceLayoutModel``
- ``CallGraphLayoutModel``
- ``PackageLayoutModel``
- ``DiagramLayoutModel/GroupingBox``

### Views & styling

- ``DiagramSnapshotView``
- ``SequenceDiagramSnapshotView``
- ``PackageDiagramSnapshotView``
- ``CallGraphSnapshotView``
- ``ClassDiagramConfiguration``
- ``DiagramPalette``
