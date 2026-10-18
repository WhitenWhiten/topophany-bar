# topophany-bar

A native macOS menu bar app and desktop widgets for [Topophany](https://github.com/WhitenWhiten/topophany). The status item shows, at a glance, what your collector concludes about your network. One click opens a panel with what needs attention, the vantage points that see it, your applications, pinned servers and this Mac. Widgets pin the same cards to the desktop.

It shows what `topo` concludes and never decides anything itself. Every state, count and health comes from `topo monitor stream`, which the app runs as a child process.

**Status:** designed, not yet implemented. macOS 26 or later.

## Read first

| | |
|---|---|
| [`design/DESIGN.md`](design/DESIGN.md) | The design: surfaces, themes, widgets, architecture, phases |
| [`docs/PROTOCOL.md`](docs/PROTOCOL.md) | The contract with `topo monitor stream` (authoritative) |
| [`design/index.html`](design/index.html) | HTML previews of every surface, state and theme; open in a browser |

`design/shots/shot.sh PAGE OUT.png WIDTH HEIGHT [SCALE]` renders a preview page to PNG with a headless Chromium. For example: `design/shots/shot.sh "playground.html?scenario=incidents&theme=tui" /tmp/p.png 1440 1400 2`.

## Requirements

- macOS 26 or later.
- `topo` with `monitor stream` (`topo monitor stream --capabilities` must print `"protocol":1`).
- A saved client profile (`topo login`). The app never reads or stores a token; `topo` does.
