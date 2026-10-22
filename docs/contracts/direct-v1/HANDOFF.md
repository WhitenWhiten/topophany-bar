# Bar Direct v1 handoff

Local delivery: 2026-10-22 (America/Los_Angeles). Implementation is in
`/Users/whiten/Desktop/topophany-bar`; delivery is a local implementation commit only, with no push,
publish, install, Team ID or entitlement changes. Initial HEAD and worktree were
`0345dc7c0cb6186e181c8676d9539c11c887c01a` and clean. Source and test files hash to
`2e9dd3cda6908bc582e2d43a0b732f0b866bf66c8b154b2d0f02e495081e211c` (182 files).
The hashing recipe and full captured provenance are in
[`build/direct-evidence/provenance.json`](../../../build/direct-evidence/provenance.json).

## User flow and implementation

Settings → Data sources → Beszel direct → Add Beszel → Test connection → choose
systems → Save → CPU/memory/primary-disk cards. This was exercised in the real
native app using real topo and the Go literal-loopback Hub, including stable
system-ID selection, editing, saved authentication, reauthentication, source
permission errors, stale samples and removal of both one source and the last
source. No real Beszel Hub was used.

- D1 / config API 1 is capability-negotiated, keeping client/preview and Settings
  migration. Direct templates use sources.status, servers.list and deduplicated
  resource cards; collector preferences remain saved. Excess rows fail explicitly.
- One-shot commands use bounded multiplexed IO, stdin-only authentication, a
  45-second deadline, cancellation, exit/envelope/request-ID checks and no stderr
  body display. Unknown outcomes and conflicts read the profile before review;
  adding a new source is disabled until a successful profile list.
- Secrets remain in the editor session and clear on close/cancel/success. Source
  IDs survive retries. Changing a Hub while using saved authentication requests
  reauthentication rather than sending the old credential to a changed address.
- Stream replacements remain in one process. Corresponding running frames confirm
  installation. Request/process generations reject stale results; source+dataset
  partitions reader history. Pins are scoped by stable mode/profile, widget node
  choices by dataset. Retry and wake use debounced nonces. Terminal arguments have
  source/profile/observer navigation, without secrets or a Hub URL.
- Acquisition state is its own section model. Counts are Go's; Connected is not
  All clear, and source errors do not declare machines down. Native/Cards and
  Terminal/Cells retain their theme tokens, provider semantics and origin badges.
- Direct widgets show As of resource snapshots. Per-widget row/resource deadlines
  create expiry entries, without heartbeat grace. Safe snapshot writes and
  WidgetKit reload requests are separate. Widgets do not poll the Hub.

## Exact Go pair and contract

| Item | Identity / SHA-256 |
|---|---|
| Go HEAD (dirty, uncommitted) | `7e7fdb11358fd8c49b07ac7e840a2cbe72826f0b` |
| Go runtime source, 744 files | `7db239d5e1f053733f22ec749232fd65b8ff40ec4c7b287ebf7215a86657560c` |
| `/Users/whiten/Desktop/topophany/bin/topo` | `6deb1e1be747cc48ec9ef69d77ade842abbf3fa6a654fed4e2b4e4885d9366c9` |
| D1 manifest, 28 fixtures | `63e7ad110dff62927f4eca7f4516ae678d65596412097412eb8790f51d3cdbd7` |

The runtime hash was independently reproduced using the Go handoff's recipe:
sorted regular files under cmd/ and internal/, plus existing go.mod/go.sum;
relative POSIX path, NUL, bytes, NUL. The binary and manifest match Go's finalized
handoff. Canonical contract.md, manifest and every listed fixture are copied
byte-for-byte. Tests use those same files directly and verify all hashes.
The stream-request-error fixture correctly has no installed source/dataset;
only running frames require a nonempty dataset identity. Development-only fixtures
remain explicitly isolated under Tests/Fixtures/DirectDevelopment.

## Verification run here

| Check | Result / local evidence |
|---|---|
| Swift 6.4 package build | Pass, build/direct-final-build.log |
| Complete Swift package tests | 332 passed, build/direct-final-all-tests.log |
| Latest direct visual/timeline tests | Pass, build/direct-last-visual-tests.log |
| XcodeGen + unsigned App/extension build and App tests | 12 passed, build/direct-final-xcode.log |
| Real Swift SourcesClient + ProcessEngine | Pass, build/direct-final-real-swift.log |
| Go real-binary harness | 7 groups passed, build/direct-final-go-harness/results.json |
| Canonical fixture bytes, decoders and rendering | Pass, build/direct-final-contract.log |
| Diff whitespace / AppKit-free Sources boundary | Pass |

The full package run covers existing client/preview renderers, models, reader,
process behavior and widgets. Targeted checks after the full run cover the final
UI route/isolation changes and direct snapshots. Real Swift integration includes
password/token/saved authentication, exact node IDs, loading/ready/resource cards,
profile CAS rejection, retry, one stream process, removal and stable dataset on
reauthentication. The Go harness also covers 20-object request budgets, projection
changes without collection, multi-source isolation, unchanged-record expiry and
recovery, CLI/history/file modes, real PTY TUI, slow stdout/EOF/EPIPE/signals.
Go's own wider verification is recorded in its separate repository HANDOFF; this
Bar executor did not run scripts/verify.py or modify that repository.

Reproduce the Go harness:

```sh
python3 /Users/whiten/Desktop/topophany/scripts/direct-contract.py \
  --topo /Users/whiten/Desktop/topophany/bin/topo \
  --out /ABS/TEMP/results
```

Start the Hub (ready path must not already exist):

```sh
python3 /Users/whiten/Desktop/topophany/scripts/direct-contract.py \
  --serve-fixture-hub --ready-file /ABS/TEMP/hub-ready.json --objects 2
```

Then run the Swift integration (the Hub preserves its original record time;
start a new Hub when testing fresh resources after a long delay):

```sh
TOPOPHANY_DIRECT_BINARY=/Users/whiten/Desktop/topophany/bin/topo \
TOPOPHANY_DIRECT_READY=/ABS/TEMP/hub-ready.json \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --filter DirectIntegrationTests
```

For the native app, use a temporary Settings file containing source=direct and a
profile, and launch with `-settings ABS_TEMP/settings.json -topo ABS_BINARY
-direct-root ABS_TEMP/direct`. These advanced injections are not normal Settings.

## Visual evidence and limits

- Baseline production panels/widgets and Settings HTML:
  [build/direct-baseline](../../../build/direct-baseline).
- Actual Settings source window:
  [settings-sources-real.png](../../../build/direct-evidence/settings-sources-real.png).
- Final native Settings capture:
  [settings-sources.png](../../../build/direct-evidence/app-windows/settings-sources.png).
- Direct production ImageRenderer matrices and canonical-frame panels:
  [Tests/Snapshots/out](../../../Tests/Snapshots/out), prefixed direct- or contract-stream-.
  The generated set includes all six themes, English/Japanese/Simplified Chinese,
  Native light/dark, acquisition/expiry states and affected widget sizes.
- Representative Native/Terminal states, all six themes and three-language Widget
  examples were opened and inspected. The old client README galleries were
  regenerated and visually compared with the baseline; no unrelated layout
  redesign was observed. PNGs are not asserted byte-identical.
- The real native form and live resource panel were inspected with the native UI
  tool. The native panel showed CPU 25%, memory 50%, disk 25%; later the same Hub
  record expired to unknown. Source permission failure and same-name source
  separation were inspected, then sources were removed with native confirmation.
- AppKit cache-display panel PNGs can omit compositor glass/text and are not used
  as proof of the complete native panel. The production ImageRenderer matrix is
  the reliable archived rendering evidence. A separate system compositor/menu-bar
  recording was not archived. Existing Reduce Motion policies and disabled-motion
  model tests remain; no global accessibility preference was changed.
- **System desktop Widget loading is unverified**: this build uses TOPOPHANY_SIGN=NO
  and has no authorized App Group. The extension builds and timeline/ImageRenderer
  checks pass; no Team ID, entitlement, signing permission or installation was added.

## Isolation audit deviation

An early native direct test still inherited AppModel's old automatic
`topo monitor stream --profiles` call. That client-only command may read the user's
default credential file, so this did not meet the requested isolation boundary.
The executor did not inspect or display that file's contents, and no token or
password was returned by the profiles API or written by this call. Whether the
file existed or was read was deliberately not investigated further.

The call is now restricted to normal client launches. Direct and isolated test
instances do not enumerate client credentials; isolated client fallback explicitly
names an absent temporary client-credentials path. A regression test uses a marker
executable to prove neither direct nor isolated-client mode invokes --profiles.
All subsequent verification uses temporary roots. Configuration-command stderr
bodies are discarded, and saved Settings/handoff models exclude authentication.
This audit note is retained rather than claiming that the earlier run never
could have accessed the default store.

All test fixture Hub processes were stopped after verification. Synthetic ready files,
private direct roots and duplicate smoke app bundles were removed; public logs,
source, render matrices and the unsigned Xcode build remain.
