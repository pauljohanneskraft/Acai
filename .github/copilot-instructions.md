# Review instructions

`CLAUDE.md` at the repository root is the source of truth for this codebase's conventions; review
against it.

For any change under `App/AcaiUITests/`, or any app change a journey drives, check the rules in its
"Writing a UI journey" section and flag:

- a tap outside `tapWhenReady` / `tap(_:until:)`, or `tap(_:until:)` on an action with a side effect
- a wait outside `waitOrFail` / `waitForDisappearanceOrFail` / `AsyncOperation.waitUntilLoaded`, a
  `Thread.sleep` in a journey, or a timeout other than `.uiTransition` / `.uiWork`
- a raised timeout, a widened screenshot threshold, or a retry added to make a journey pass
- a new async operation without `.loading`/`.loaded`/`.error` identifiers, or a new interactive
  element without an accessibility identifier
- a screenshot state that could capture per-run content (paths, dates, IDs)
- navigation or fixture setup copied between journeys instead of reusing a screen action or
  `Support/SeededFixture.swift`
- selecting a just-created item directly instead of through `ProjectBrowserViewModel.open(_:)`
