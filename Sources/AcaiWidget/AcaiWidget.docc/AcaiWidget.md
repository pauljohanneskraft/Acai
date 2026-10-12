# ``AcaiWidget``

A codebase's state as of its last analysis, on the iOS and iPadOS Home Screen or the macOS desktop
and Notification Centre.

## Overview

`AcaiWidget` is a library target, like [AcaiApp](/documentation/acaiapp/): the shipped widget
extensions are thin `@main` `WidgetBundle` shells in `App/Widget` that both wrap
``CodebaseStateWidget``. It depends only on
[AcaiAppModel](/documentation/acaiappmodel/) — an extension links as little as it can, and it
needs nothing from the analysis engine.

## What it shows

One chosen codebase: its name, when it was last analysed, whether the code had changed since, and
what that analysis found — how many types, how many findings, and how many of those were critical.
A count the app has not computed yet is left out rather than shown as zero, which would read as
"found nothing".

Tapping the widget opens **that codebase** rather than the app's front door, through the
`acai://codebase/<uuid>` deep link that `AcaiAppModel`'s `AppAddress` builds.

## Why it is a snapshot, never live

A widget runs in its own process, outside the app, with no access to the folder a codebase points
at — not the security-scoped bookmark that reaches a picked folder, and no analysis engine to run
over it. Everything it shows was therefore written out by the app beforehand:
`CodebaseWidgetSnapshotStore` keeps one JSON file in the App Group container
(`group.de.kraftsoftware.Acai`), which the app rewrites whenever it learns something new about a
codebase and the widget only ever reads.

So the widget cannot discover that code has changed; it can only report whether the app had found
it changed the last time it looked. That is why every analysed state carries an explicit "as of the
last analysis" footnote, and why a codebase the app has never compared against its analysis says
"Changes not checked" rather than claiming either freshness or drift. The medium widget also says
when that check ran, and every age ("Analysed 2 hours ago") is kept current by the system between
timeline reloads rather than frozen when the entry was built.

The shared file holds each codebase's name, pinned revision, dates and counts — no source, paths or
findings text — and a file the widget can't decode, or one written by a newer app, is ignored.

## Choosing a codebase

``SelectCodebaseIntent`` is the widget's configuration. Its picker is populated from the same
snapshot file rather than from the app's store, because the app is usually not running when the
picker opens. A widget not yet configured shows the codebase analysed most recently, so it says
something useful before it is ever edited; one pointing at a codebase since deleted says so, and
offers editing it.

## Topics

### The widget

- ``CodebaseStateWidget``
- ``SelectCodebaseIntent``
