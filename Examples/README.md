# Examples

Small, self-contained sample code used to generate the diagrams in the
top-level [`README.md`](../README.md). It's intentionally tiny but exercises
every relationship UML draws — inheritance, composition, and dependency —
across two languages.

## `MediaLibrary/`

A toy media-playback domain, mirrored in two languages so a single run shows
UML's multi-language output side by side:

- **`Swift/`** — `Playable` (protocol) ← `MediaItem` ← `Song` / `Podcast`
  (inheritance), `Playlist` holding `[MediaItem]` and `Library` holding
  `[Playlist]` (composition), and `Player` depending on `Library` / `Playable`
  (dependency). Plus a `Genre` enum.
- **`Kotlin/`** — `AudioSource` (interface) ← `Track` ← `LiveTrack` /
  `RecordedTrack`, an `Album` data class composing `Track`s, a `Streamer`
  depending on `Album` / `AudioSource`, and a `Quality` enum.

This is sample input, not a buildable package — there's no `Package.swift` or
Gradle build here, and it isn't part of the UML test suite. It exists purely so
the README images stay reproducible.

## Regenerating the README diagrams

From the repository root, with the CLI built (`swift build`, then use
`.build/debug/UMLCLI`, or install it as `uml` via `./Scripts/cli_install.sh`):

```sh
# Headline: both languages, grouped by directory, full member detail
uml image --source Examples/MediaLibrary --grouping directory \
    --output Documentation/Images/diagram-full.png --scale 2

# Detailed close-up: Swift only
uml image --source Examples/MediaLibrary --language swift --grouping none \
    --output Documentation/Images/diagram-swift.png --scale 2

# Overview: relationships only, members hidden
uml image --source Examples/MediaLibrary --grouping directory --hide-members \
    --output Documentation/Images/diagram-types-only.png --scale 2
```

> `uml image` is macOS-only — it renders with SwiftUI's `ImageRenderer`, which
> needs a window-server session. On Linux, use `uml diagram … | dot -Tpng` to
> produce images via Graphviz instead.
