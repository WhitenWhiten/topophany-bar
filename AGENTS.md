# Engineering rules

Preserve these performance boundaries when changing the menu bar, panel, themes
or maps. Reuse existing mechanisms; keep local changes local instead of adding
state layers, cache frameworks or background loops.

## State and invalidation

- Identify each state's update frequency, owner and subscribers before changing
  it. Keep scroll, drag and zoom state in the smallest interaction subtree;
  separate it from data refreshes and configuration.
- `PanelScroller` owns scroll-position bindings and writebacks. Only the footer
  and fade observe scroll edges. Panel roots, card content and Terminal scenes
  must not observe scroll positions or edges.
- Give expensive content only the inputs it needs. Scroll commands, clock ticks,
  hover and local readings must not rebuild unrelated sections or maps through
  an entire model or render context.
- Preserve stable view identity and deterministic drawing order. `Equatable`
  must cover every visual input without letting unrelated fields defeat reuse.
  Never omit a visual dependency to conceal redraws.

## Layout and drawing

- SwiftUI geometry owns window size. Coalesce writebacks and skip unchanged
  values. Allow one initial measurement when opening a window; routine refreshes,
  scrolling and dragging must not call `fittingSize`, force synchronous subtree
  layout or call `setFrame(display: true)` for an unchanged frame. Avoid feedback
  between measurement and window sizing.
- Terminal sections and pinned bands use canvases with their actual dimensions.
  Do not paint the whole panel and then clip it to simulate local drawing.
  Unchanged sections retain prepared drawing data and rasters; maps have an
  independent drawing boundary.
- Frame callbacks perform only necessary interpolation, transforms and drawing.
  Keep file access, decoding, sorting and reusable expensive preparation outside
  these callbacks. Move heavy preparation off the UI thread when safe.
- Keep `LandCoverage` row and column projection preparation and the existing
  nine coast samples per dot. Do not restore inverse projection per subsample
  inside the drawing loop.
- Bound caches and invalidate them by actual dependencies. Keys include relevant
  data, theme, language, scale, focus and dependent absolute coordinates. Reused
  drawing must preserve hit areas and keyboard focus regions.

## Animation and lifetime

- Scope animations to changing local properties and explicit trigger values.
  Do not apply implicit animation to an entire model at the panel root. Scroll
  commands move the viewport without becoming inputs to expensive drawing.
- Use finite easing durations for expensive map redraws; avoid spring tails
  that keep drawing. Dragging and wheel input follow the gesture directly.
  Respect Reduce Motion. Preserve native layers and decoded frame reuse for
  menu bar animations instead of rebuilding SwiftUI views every frame.
- Give animations, timers, observers and async tasks explicit lifetimes. Work
  serving only a particular view stops when that view closes or becomes hidden.
  Reopening must not accumulate callbacks; stale async results must not replace
  newer state.
- Async drawing, throttling and caching do not justify broader invalidation.
  Do not hide stalls by reducing interaction responsiveness or visual quality.

## Change review

For changes to these paths, explain what triggers updates, which views become
invalid, how much area redraws, whether work per frame increases, and when
resources are released. Keep the implementation proportional to the change.

Manually check the affected interactions. When investigating a hot path, reuse
the [existing diagnostics](docs/DEVELOPMENT.md#panel-performance) and compare on
the same machine, build configuration and scenario. Do not add CI, monitoring
frameworks or redundant tests as a substitute for engineering judgment.
