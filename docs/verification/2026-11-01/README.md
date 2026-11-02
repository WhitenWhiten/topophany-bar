# Usability verification, 2026-11-01

The later [live collector expiry investigation](expiry-root-cause.md) identifies
and repairs a companion publication-cadence bug; its evidence and local
installation are separate from the synthetic UI verification below.

Real isolated Debug app, Chinese UI, Apple M6/macOS arm64, synthetic fixtures.
`panel-interactions.json` records 10 wheel and 10 map interactions per theme,
including main-thread gaps and existing drawing counters. No claimed speedup or
60 fps guarantee; other verification workloads may have been active.

`hidden-lifecycle.json` records two isolated 60-second runs: after three ordinary
open/close cycles, and after twenty rapid cycles. AppKit window snapshots verified
the panel hidden before and after both samples. Both had zero drawing, layout or
scene counters. Rapid-cycle RSS was 87.1 to 86.9 MiB; CPU time increased by 0.13 s.
The menu bar remained visible and functional; reopening was checked afterwards.
An earlier sample during concurrent UI testing lacked window-state capture and
showed unexpected drawing. It was not reproducible in either isolated repeat and
is not used as acceptance evidence. No speculative rendering change was made.

Existing diagnostics were used; no production setting or connection was touched.
The temporary apps were terminated. `RefreshTests` additionally advances a manual
clock eight hours and verifies expiry, coalesced wake retries and a single engine
across twenty reopenings. This is not actual machine sleep/wake acceptance.

Final regression: 383 Swift package tests and 20 Xcode application tests passed.
The signed universal local artifact remains documented in
[0.2.0-local.md](../../releases/0.2.0-local.md); subsequent companion changes are
contract fixtures, tests and verification documentation only.
