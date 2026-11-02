# Content continuity during collector read gaps

Follow-up to the [publication expiry repair](expiry-root-cause.md). The user
reported a roughly 20-second update gap during which both the panel and desktop
widgets became empty. A subsequent three-minute live stream captured one
`http/connection_rotating` read failure; it did not reproduce that entire
reported 20-second interval.

The remaining empty-state path was identified in code: `stream.openSource`
discarded its preceding snapshot on any failed read, and widget handoffs kept
only the latest frame, which then contained null rows. The publication fix alone
could not prevent this path. WidgetKit also decides when reload requests are
served, so clearing its handoff can outlive a transient network error.

## Changes

The companion changes are committed in topophany as `02af7d1`.

- Topophany retains an already acquired snapshot on transient read failure,
  while preserving its original deadlines and reporting the failed acquisition.
  Expired values remain withheld. Authorization and malformed/foreign responses
  do not inherit live evidence. The explicit `503 connection_rotating` response
  gets the same single bounded retry as `snapshot_busy`, within the caller's
  existing deadline and after trying eligible failover endpoints.
- The bar's reader owns one usable collector snapshot. Panel/widget presentation
  can show it after expiry as **Last snapshot**, with time and acquisition state.
  Real-time evaluation, alerts and reload signatures continue using strict
  readings. Source/scope/template changes discard history. There is no unbounded
  history, new polling loop or timer.
- The widget handoff persists that snapshot through empty frames. Individual
  card widgets reserve a history-label line; status widgets use their headline.
  Historical widget colors are subdued, and ages continue to advance. Direct
  source semantics are unchanged.

The existing app refresh builds presentation models only while the panel or
settings are visible. History updates only when a usable collector frame arrives
and is released on scope/template changes. Historical display uses the normal
section rendering boundaries; scroll state and map interactions remain local.
No work was added to animation frame callbacks.

## Verification

The existing strict expiry, alert, section and direct-widget tests remain in
place. New tests inject a 20-second failure, round-trip a handoff, verify retained
status/cards and explicit historical timestamps, then restore fresh data. They
also verify scope/template isolation and that live values remain withheld.
Backend tests cover failed-read deadline preservation, expiry, authorization
rejection, and bounded/recovering connection-rotation retries.

356 non-snapshot Swift tests and 22 Xcode application tests passed. The Chinese
continuity snapshots cover Native and Terminal panels plus status, server and
map widgets. Images were inspected, including the reserved header in a small
server widget. Backend client/stream suites and race checks passed, as did all
46 Go packages with tests. Isolated Native and Terminal windows retained counts,
readings and the map after 25 seconds without new data; closing and reopening
preserved the content.

Local screenshots, window diagnostics, test logs, installation metadata and
rollback copies are retained under `build/continuity/`. App build 7 includes the
widget extension with the same Developer ID and App Group as the installed app.
The local companion is labelled `1.5.3+continuity-fix`.

This prevents a read gap from replacing useful content with an empty layout;
it does not guarantee a network request finishes within a fixed number of seconds.
