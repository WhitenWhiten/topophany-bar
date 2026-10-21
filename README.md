# topophany-bar

A native macOS menu bar app and desktop widgets for [Topophany](https://github.com/WhitenWhiten/topophany). The status item shows, at a glance, what your collector concludes about your network. One click opens a panel with what needs attention, the vantage points that see it, a map of where your servers are, your applications, pinned services and servers, and this Mac. Widgets pin the same cards to the desktop.

It shows what `topo` concludes and never decides anything itself. Every state, count and health comes from `topo monitor stream`, which the app runs as a child process.

**Status:** v1, not yet released. macOS 26 or later.

In Settings › General › Keyboard shortcut, click Record shortcut to choose a global key that opens or closes the panel. Esc cancels and the clear button removes it. Conflicts with enabled system shortcuts, Topophany commands and registered global hotkeys are rejected. Other apps' internal shortcuts cannot all be checked.

Like it? ★ [Star Topophany](https://github.com/WhitenWhiten/topophany), the project this bar is built on.

## Read first

| | |
|---|---|
| [`design/DESIGN.md`](design/DESIGN.md) | The design: surfaces, themes, widgets, architecture, phases |
| [`docs/PROTOCOL.md`](docs/PROTOCOL.md) | The contract with `topo monitor stream` (authoritative) |
| [`design/index.html`](design/index.html) | HTML previews of every surface, state and theme; open in a browser |

`design/shots/shot.sh PAGE OUT.png WIDTH HEIGHT [SCALE]` renders a preview page to PNG with a headless Chromium. For example: `design/shots/shot.sh "playground.html?scenario=incidents&theme=tui" /tmp/p.png 1440 1400 2`.

## Requirements

- macOS 26 or later.
- `topo` with `monitor stream` (`topo monitor stream --capabilities` must print `"protocol":1`). Without one, the app downloads it from [topophany's releases](https://github.com/WhitenWhiten/topophany/releases) when you click Download topo, and checks its SHA-256 first.
- A saved client profile (`topo login`, or Sign In in Settings, which runs it in your terminal). The app never reads or stores a token; `topo` does.

## Building

The packages build and test with SwiftPM; the app and the widget extension build with the Xcode project, which XcodeGen generates from `project.yml`.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test
xcodegen generate
xcodebuild -project topophany-bar.xcodeproj -scheme topophany-bar -configuration Debug -derivedDataPath build/DerivedData build
```

Builds sign with the team in `project.yml` (`TOPOPHANY_TEAM`), with an App Group the app and the widgets share. Add `TOPOPHANY_SIGN=NO` to build ad hoc with no team or entitlements: the app runs, and macOS ignores the widgets. `scripts/release.sh` signs with Developer ID, notarizes, and packs the app into a disk image to drag to Applications. `scripts/make-dmg.sh APP OUT.dmg` packs any build the same way, for a look; `swift scripts/make-dmg-background.swift` redraws the image's window.

## License

topophany-bar is source-available under the [PolyForm Noncommercial License 1.0.0](LICENSE): you may build it, run it and change it for any noncommercial purpose. Commercial use, including use at work for a company, needs a separate license; ask in an [issue](https://github.com/WhitenWhiten/topophany-bar/issues).

The provider logos and what came with them are under their own licenses: see [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md). [Topophany](https://github.com/WhitenWhiten/topophany) itself is under the MIT License.
