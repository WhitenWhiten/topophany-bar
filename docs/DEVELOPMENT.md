# Development and releases

Build, test and package topophany-bar. For features and first-time setup, see the [project README](../README.md). Run the commands below from the repository root.

Prerequisites: macOS 26 or later, full Xcode with Swift 6.2 or newer and a macOS 26 SDK or newer, and [XcodeGen](https://github.com/yonaskolb/XcodeGen). Install XcodeGen with `brew install xcodegen`.

## Read first

| | |
|---|---|
| [`design/DESIGN.md`](../design/DESIGN.md) | The design: surfaces, themes, widgets, architecture, phases |
| [`docs/PROTOCOL.md`](PROTOCOL.md) | The contract with `topo monitor stream` (authoritative) |
| [`design/index.html`](../design/index.html) | HTML previews of every surface, state and theme; open in a browser |

`design/shots/shot.sh PAGE OUT.png WIDTH HEIGHT [SCALE]` renders a preview page to PNG with a headless Chromium. For example: `design/shots/shot.sh "playground.html?scenario=incidents&theme=tui" /tmp/p.png 1440 1400 2`.

## Building

The packages build and test with SwiftPM; the app and the widget extension build with the Xcode project, which XcodeGen generates from `project.yml`.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test
xcodegen generate
xcodebuild -project topophany-bar.xcodeproj -scheme topophany-bar \
  -configuration Debug -derivedDataPath build/DerivedData TOPOPHANY_SIGN=NO build
open build/DerivedData/Build/Products/Debug/topophany-bar.app
```

The commands above build ad hoc with no developer team or entitlements: the app runs, but macOS does not load the widgets. To build with widgets, omit `TOPOPHANY_SIGN=NO` and set `TOPOPHANY_TEAM` to your own Apple Developer Team ID. The app and widget extension need a shared App Group belonging to that team. `scripts/release.sh` signs with Developer ID, notarizes, and packs the app into a disk image to drag to Applications. `scripts/make-dmg.sh APP OUT.dmg` packs any build the same way, for a look; `swift scripts/make-dmg-background.swift` redraws the image's window.

## Panel performance

Follow the state, layout, drawing and animation boundaries in the repository's
[engineering rules](../AGENTS.md). The commands below support targeted diagnosis
when changing a hot path; they are not a required suite for unrelated edits.

Build Debug as above, then measure the real native scroll view with synthetic
data and temporary settings. The installed app, saved connection and credentials
are left alone. Both theme renderers run by default; `--theme` can select any
built-in theme, and `--language` accepts `en`, `ja` or `zh-Hans`.

```sh
python3 scripts/check-panel-performance.py \
  build/DerivedData/Build/Products/Debug/topophany-bar.app \
  --input leap --out build/panel-performance/leaps
python3 scripts/check-panel-performance.py \
  build/DerivedData/Build/Products/Debug/topophany-bar.app \
  --input wheel --out build/panel-performance/wheel
```

Each run records ten downward and upward scrolls, actual offsets, window and
hosting bounds, main-thread sampling gaps, view rebuilds and drawing costs.
The script warms the first render, rejects stationary scrolls and invalid hosting
bounds, and saves CSV samples and JSON summaries. Sampling gaps detect main-thread
stalls; they are not GPU frame-rate measurements. An optional `--max-gap-ms 25`
enforces a local stall budget. `--topo /ABS/PATH/topo` uses that executable's
synthetic preview network instead of the bundled fixture.
`--input map` measures keyboard zoom in both directions, including its drawing
costs; it requires a scenario with a map.

`PanelScrollTests` exercises the real hosted SwiftUI binding graph.
`PanelLayoutTests` checks window bounds after opening, resizing, theme changes,
data refreshes and reopening. Pixel tests cover Terminal cropping in all three
languages. The debug driver's `perf start` keeps its panel open during a capture;
`perf stop` writes `performance.json` and restores ordinary outside-click closing.
All performance probes are excluded from Release builds.

## README screenshots

The README's illustrations render the production SwiftUI views with fixed English demo data and a fixed clock. The hero and the panel themes use the `degraded` and `incidents` fixtures; the widget gallery uses `clear`. The Beszel and Komari image reads `Tests/Fixtures/DirectDevelopment/mixed.json`, a direct profile with a Beszel Hub and a Komari server.

Generate and replace every image with one command:

```sh
./scripts/make-readme-screenshots.sh
```

The script runs from any working directory, finds full Xcode at `/Applications/Xcode.app` by default, and honors `DEVELOPER_DIR` for a different installation. It requires macOS 26+ and the build toolchain described above; no collector, credentials, signing, screen-recording permission or running app is needed.

To preview changes without replacing the README assets, pass an output directory (relative to your current directory, or absolute):

```sh
./scripts/make-readme-screenshots.sh /tmp/topophany-readme-preview
```

Outputs:

- `hero.png`: the menu bar with White Night, the Native panel centered beneath it as the app places it, and widgets on the desktop.
- `white-night.gif`: White Night's 24-second loop through clear, degraded, down and clear, at 4× so each dot of its dither lands on 2 × 2 pixels. Moons dissolve as the app plays them, and the words roll.
- `menu-bar.png`: every status as White Night, the globe and the Terminal chip, and This Mac's readings beside the item, at 4×.
- `direct-sources.png`: direct mode with both kinds of source, in the panel and two widgets.
- `themes.png`: the panel's status, attention and This Mac sections in all six built-in themes.
- `widget-gallery.png`: ten widgets covering all five types and six themes.
- `icon.png` and `icon-dark.png`: the app icon as macOS draws it in light and dark, exported at 256 pixels by Icon Composer's `ictool`.

The layouts and scenario choices live in `Tests/TopophanyThemesTests/ReadmeSnapshots.swift`. The script renders into a temporary directory and only copies the images after every render succeeds, so an unsuccessful run cannot reuse stale screenshots. `TOPOPHANY_SNAPSHOT_DIR` overrides the snapshot output directory for this run; ordinary snapshot tests still write to `Tests/Snapshots/out`. Native's panel renders translucent without the window's blur, so keep panels clear of widgets in a composition.

Inspect every generated image before committing them. Keep private network data and credentials out of documentation screenshots.

## Releasing on GitHub

The [release workflow](../.github/workflows/release.yml) runs when you push a tag in
the form `vMAJOR.MINOR.PATCH`, for example `v0.1.0`. It tests the packages on
macOS 26, builds a universal app for Apple Silicon and Intel, signs with Developer
ID, notarizes and staples both the app and the DMG, and publishes the DMG and
`sha256.txt` as a GitHub Release. The tag selects the exact source commit and the
app's version; it does not build the current tip of the default branch.

Before the first release, enable GitHub Actions and add these **repository
secrets** under Settings → Secrets and variables → Actions:

| Secret | Value |
|---|---|
| `DEVELOPER_ID_CERTIFICATE_BASE64` | Base64 of a Developer ID Application `.p12` export, including its private key |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | The nonempty password used to export the `.p12` |
| `APPLE_ID` | Apple Account email with access to the developer team |
| `APPLE_APP_SPECIFIC_PASSWORD` | An app-specific password for that account, used by `notarytool` |
| `APPLE_TEAM_ID` | The certificate's 10-character Apple Developer Team ID |

Export **Developer ID Application**, rather than Apple Development, from Keychain
Access with its private key. On macOS, copy the certificate's Base64 with:

```sh
base64 -i /path/to/DeveloperIDApplication.p12 | pbcopy
```

This requires Apple Developer Program membership. The workflow imports the key
into a temporary keychain and deletes it after the job. The Team ID overrides
the build's `TOPOPHANY_TEAM`; the certificate and the app/widget App Group must
belong to that team. See [GitHub's certificate setup guide](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications).
GitHub supplies the release token automatically; no personal access token is
needed. Repository or organization policy must permit the workflow's
`contents: write` permission.

Commit and push the workflow and the code you want to release, then tag that
commit (assuming the GitHub remote is named `origin`):

```sh
git tag -a v0.1.0 -m "Release v0.1.0"
git push origin v0.1.0
```

Follow **Actions → Release DMG**. After it succeeds, **Releases → v0.1.0** contains
`topophany-bar-0.1.0.dmg` and `sha256.txt`. Use a new version tag for each release;
prerelease suffixes such as `-beta.1` are not supported by this workflow.
The workflow creates a release after signing and notarization succeed, and does
not overwrite an existing release. GitHub selects the Latest release
[automatically by date and version](https://cli.github.com/manual/gh_release_create).

## Direct development and acceptance

Use only a synthetic loopback Hub and a temporary direct root. Never point tests
at a real account or the user's credentials. The canonical fixtures are in
`docs/contracts/direct-v1`; `DirectContractTests` checks every manifest SHA-256.
`Tests/Fixtures/DirectDevelopment` is explicitly a separate development double,
never backend acceptance evidence.

```sh
python3 /Users/whiten/Desktop/topophany/scripts/direct-contract.py \
  --serve-fixture-hub \
  --ready-file /ABS/TEMP/hub-ready.json --objects 2
```

The ready file is 0600 and contains only synthetic login information. Add
`--scenario forbidden`, `auth_required`, `missing`, `stale`, `rate_limited` or
`unavailable` to exercise acquisition states; `--delay-seconds` controls latency.
Stop the process with SIGTERM. A ready Hub deliberately preserves its record's
created time: start a new fixture Hub for a fresh sample. Re-reading an unchanged
record must eventually produce stale resources.

```sh
TOPOPHANY_DIRECT_BINARY=/Users/whiten/Desktop/topophany/bin/topo \
TOPOPHANY_DIRECT_READY=/ABS/TEMP/hub-ready.json \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --filter DirectIntegrationTests
```

This runs SourcesClient and ProcessEngine against real commands, installs and
replaces requests in one stream, tests CAS/retry, then removes its temporary source.
Without those environment variables it does not contact a backend. The Go harness
can also run its complete suite with `--topo ABS_BINARY --out ABS_TEMP_DIR`.

For Komari, `Tests/Fixtures/DirectDevelopment/fake-komari.py` serves Komari 1.6's
three read endpoints on literal loopback, with two public servers and one hidden.
It is a development double; Go's `scripts/accept_komari.py` runs the official
binary. Use a `topo` whose capabilities list `komari`:

```sh
python3 Tests/Fixtures/DirectDevelopment/fake-komari.py \
  --ready-file /ABS/TEMP/komari-ready.json
TOPOPHANY_DIRECT_BINARY=/ABS/topo \
TOPOPHANY_KOMARI_READY=/ABS/TEMP/komari-ready.json \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --filter DirectIntegrationTests
```

It drives the source editor as the sheet does: public servers without a key, a
rejected key, then the API key, save, editing with the saved key, a stream to
ready Komari cards, and removal. SIGTERM stops the server and removes its ready file.

A Debug app accepts `-settings ABS_TEMP/settings.json -topo ABS_BINARY
-direct-root ABS_TEMP/direct` to isolate both public Settings and Go credentials.
Normal launches omit direct-root. `AppModel` also accepts a clock, source command
client and engine factory for deterministic state tests. Existing `-snapshot DIR`
now includes Data sources; the debug driver's `panelshot` and `settingsshot` capture
only the test app's own windows. Use PID-directed debug commands when several
copies run. No signing team, entitlement or installed app change is needed.
