# ``AcaiRender``

Lay out and render a diagram straight to a **PNG** — no Graphviz required. Apple platforms only.

## Overview

`AcaiRender` is the visual half of Açaí. It owns the SwiftUI diagram views, a Sugiyama-style
hierarchical **layout engine**, the image renderer that turns either into a PNG, and the
**Codebase Atlas** that bundles a whole codebase into one PDF. It's shared by every front end: the
macOS app's canvas (drag, resize, group), the `acai image` / `acai atlas` CLI commands and the
`acai_image` / `acai_atlas` MCP tools — so a headless export matches what you'd see on screen,
because it runs the same layout and the same views.

> **Apple platforms only.** Rendering goes through SwiftUI's `ImageRenderer`, which needs a
> window-server session. On Linux, generate DOT with [AcaiDiagram](/documentation/acaidiagram/) and
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
- **The Codebase Atlas** — ``AtlasDocument`` bundles one codebase's diagrams, statistics and
  findings into a multi-page PDF. The caller supplies the rendered diagram pages, so the app
  exports the user's saved diagrams and canvas positions while ``AtlasDiagramSet`` renders the
  default class diagram, package graph and call graph headlessly for `acai atlas` and `acai_atlas`.
  ``AtlasFinding`` is also where the app's Findings screen takes each finding's severity and wording
  from, so the screen and the export always agree.

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

### The Codebase Atlas

- ``AtlasDocument``
- ``AtlasDiagramPage``
- ``AtlasDiagramSet``
- ``AtlasAnalysis``
- ``AtlasStatistics``
- ``AtlasFinding``
- ``AtlasFindings``
- ``PagedSection``
- ``PDFDocumentWriter``

### Views & styling

- ``DiagramSnapshotView``
- ``SequenceDiagramSnapshotView``
- ``PackageDiagramSnapshotView``
- ``CallGraphSnapshotView``
- ``ClassDiagramConfiguration``
- ``DiagramPalette``
