# Collector expiry investigation

Investigated the installed 0.2.0 (6) app and its actual `~/.local/bin/topo`
1.5.3 companion on November 1, 2026 (November 2 UTC). This investigation used
read-only live collector requests, unlike the synthetic UI checks in this
directory. It did not change collector configuration, credentials or app settings.

## Cause

The collector snapshot lifetime is 15 seconds. The monitor fetches on a
five-second schedule, but its publication policy could hold a successful new
read until the ten-second display cadence. With read latency and the one-second
publication tick, a previously published snapshot could expire before the next
frame reached the app. The Swift reader correctly withheld it at `valid_until`.

`monitor.ShouldPublish` compared health, freshness and values, but ignored
renewed row deadlines until the normal cadence. The previous app fix only showed
acquisition when reopening an already expired panel; it did not repair this
producer-side gap while the app was already running.

A captured example (UTC):

- Previous frame published at 06:02:23.021, valid until 06:02:32.115.
- A newer read completed successfully at 06:02:30.835.
- Its frame arrived at 06:02:33.022, leaving a 0.907-second expiry gap despite
  fresh evidence already being available to the producer.

The full request matching the app's supported metrics reproduced the same gap.
This was not a missing credential, stopped process or stale collector in these
captures: the affected reads all reported `ok` and newer evidence deadlines.

## Repair

The companion fix and regression tests are committed in topophany as `30ab671`
(`fix(monitor): publish renewed evidence before reader expiry`).

The companion's existing safety-state comparison now includes row and nested
deadlines that fall within the next publication window, allowing one second for
the evaluation tick. A changed deadline in that window bypasses the display
cadence. This handles renewals and shortened validity, including resources,
observers, checks and service assessments. Unchanged or distant deadlines still
use ordinary cadence; no validity, publisher lease or stale-data rule was relaxed.

The change reuses the existing traversal and scheduler. It adds no network
polling, timers, cache or UI state. An early frame goes through the app's existing
data update path; hidden panel content stays idle. There are no Swift rendering
or per-animation-frame changes.

## Verification

The regression first failed on the original code, then passed with the fix.
Coverage includes row renewal, shortened validity, unchanged evidence, distant
deadlines and six nested evidence cases. All 46 Go packages with tests passed
`go test ./...`; monitor and stream suites also passed with `-race`.

Simultaneous 180-second live runs with identical full requests:

| Companion | Frames | Expiry gaps | Longest gap |
| --- | ---: | ---: | ---: |
| Original 1.5.3 | 20 | 5 | 3.902 s |
| 1.5.3+expiry-fix | 26 | 0 | 0 s |

An expiry gap means receipt of the next frame after the previous status row's
deadline. Initial waiting frames are excluded. These bounded live runs do not
establish an indefinite network-availability guarantee.

The fixed run separately recorded one real `http/connection_rotating` failure;
the installed-binary follow-up recorded one `response/response_timeout` failure.
Both correctly withheld data as `source_unavailable` and recovered on a subsequent
read. Neither was counted as a publication expiry gap or hidden by the repair.

## Local installation

Built from companion revision `de716c3` plus the retained patch, labelled
`1.5.3+expiry-fix`. The installed binary was replaced atomically after backing up
1.5.3. Only the app's collector child was restarted; app PID 94355 and worker PID
32246 remained running. The app automatically launched replacement child 22937,
whose executable path and established collector connections were verified.
The signed app bundle remains 0.2.0 (6). No release was published.

The 60-second installed-binary follow-up had no expiry gap and ended with an `ok`
read and fresh status. Settings hashes before and after installation match.

Local evidence and rollback binary are retained under
`build/expiry-root-cause-20261101/`: `installation.json`, `summary.json`, sanitized
frame metadata, test logs, `backend.patch`, `topo-before` and `topo-fixed`.
No authentication tokens, source endpoint URLs or response bodies are retained.
