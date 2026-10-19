# topophany-bar: design notes (v1)

A native macOS menu bar app and desktop widgets for `topo`. Draft of 2026-10-18.

- **Repository and product name:** `topophany-bar`.
- **Minimum system:** macOS 26. Tested on macOS 27.

The HTML previews next to this file show the design:

| Page | What it shows |
|---|---|
| `index.html` | overview, the three looks, widgets, themes, architecture |
| `playground.html` | every state, theme and setting, live |
| `states.html` | the status item and status card in all five states |
| `widgets.html` | four sizes, both themes, every state, monochrome rendering |
| `settings.html` | the Settings window |

## 1. Goal

**At a glance, what does the collector conclude right now?** The menu bar item answers that, and it moves only while the answer is current. One click opens a panel that says where the problem is, which vantage points see it, what is affected, and how this Mac is doing. Widgets pin the same cards to the desktop.

Out of scope for v1:

- local notifications (collector webhooks already alert)
- RunCat or any file output (the stream replaces them)
- loading user theme files (the format is designed in section 8)
- the embedded engine (section 10.2)
- history charts beyond the local sparklines
- Windows and Linux

## 2. Principles

1. **Shows, never decides.** Every state, count and health comes from `topo`, computed by `internal/view` exactly as the TUI computes it. The app sets no thresholds and infers no fault.
2. **Blind is a state.** Freshness is separate from health. Past the publisher's lease or a row's `valid_until`, the row is withheld and the item turns ◌. Widgets get the same rule through their timeline (section 7.3). An old green never stays on screen.
3. **Shape, then color.** Every status mark changes shape (● ▲ ✕ ○ ◌) as well as color. Shapes belong to the renderer, so no theme can remove that distinction.
4. **Unknown is never zero.** Bars and ratios keep unknown in the denominator, drawn hollow or hatched. Unknown numbers are `null`.
5. **Local is not evidence.** This Mac's local readings carry no health, are labeled "local readings", and never leave the Mac.
6. **Beauty through restraint.** The panel is calm when things are calm: color appears only where something needs a look.

## 3. The status item

| Verdict (`view.Verdict().State`) | Badge | Color | Count | Words | Terminal chip |
|---|---|---|---|---|---|
| `clear` | ● dot | green | none | All clear | `● ALL CLEAR` |
| `degraded` | ▲ triangle | orange | warn checks | Degraded | `▲ DEGRADED` |
| `incidents` | ✕ in rounded square | red | open incidents | *n* incidents | `✖ 5 INCIDENTS` |
| `down` (no incident yet) | ✕ in rounded square | red | down checks | *n* down | `✖ 2 DOWN` |
| `incomplete`, `no-evidence`, `no-checks` | ○ ring | gray | unknown checks | Incomplete | `○ INCOMPLETE` |
| `cached`, lease lapsed, engine stopped | ◌ dashed ring | gray | none | Offline | `◌ OFFLINE` |

- **Native:** a globe in the menu bar's ink, with the badge cut into its corner.
- **Terminal:** a chip in the theme's ink.
- **Settings:** Show = Symbol, Count or Words (default Count). Status colors = on or off; with colors off the badge keeps its shape. Motion = on or off (default on). This Mac = any of CPU, Memory and Network (default none).
- **VoiceOver:** "Topophany: 5 incidents, updated 4 seconds ago." With readings shown, a second line: "This Mac: CPU 17%, memory 72%, network 1.4 MB/s in, 344 kB/s out."

### 3.1 Motion

The item moves only to say something.

| When | Native | Terminal |
|---|---|---|
| What it shows is current | the globe turns west to east, a meridian every 2.4 s; meridians come round from the left and fade toward the rim | the glyph breathes toward the glow, as the TUI's live dot does |
| Nothing current is known | the globe slows, no harder than it would from full speed in 2.4 s, and comes to rest on its still pose | the glyph rests on its tone |
| `topo` starts, or starts again shortly | the dashed ring turns | the TUI's spinner, `⠋⠙⠹⠸`, in accent2 |
| A change | the old badge shrinks away as the new one settles in, overshooting a little; the count or words roll, up for more and down for less | the new words type themselves in behind a cursor |
| A change that needs more attention | one ripple from the badge, in its color | the chip's edge lights once in the new tone |

- **More attention:** a worse mark (✕ over ▲ over the rest), or more needing attention under the same mark. Nothing else ripples.
- **Still:** with Motion off, Reduce Motion or Low Power Mode, nothing moves and a change shows at once.
- **Cost:** frames go to layers of the item's own, never to its image, which the system would lay out again each time. A turn repeats every meridian, so its 36 frames are drawn once and the system plays them; the app draws only while something else moves. Readings have a layer of their own, drawn once a sample. Nothing is drawn for motion while the displays sleep or the item can't be seen.

### 3.2 This Mac in the menu bar

CPU, memory and network can stand before the globe. They are local readings (section 5): drawn in the menu bar's ink, with no health colors and no thresholds, and sampled with the This Mac card's readings at its rate. Each is as wide as its widest value, so the item holds still as they change.

| Reading | Native | Terminal |
|---|---|---|
| CPU | the last 10 samples as bars, older ones fainter, and the total: `17%` | `CPU ▂▃▅▂▁▂ 17%` |
| Memory | used, as a ring from twelve o'clock: `72%` | `MEM ███ 72%` |
| Network | sent over received, each against its arrow: `344 kB/s ↑` `1.4 MB/s ↓` | `↓1.4M ↑344K` |

Before the first sample a reading shows `–`, never 0. In Terminal the readings take a chip of their own, before the status chip.

### 3.3 Quiet until it gets worse

Some people can't work beside a red or orange badge they already know about. They can quiet it: Quiet in the Status card (`m` in Terminal), or Quiet Until It Gets Worse in the item's right-click menu.

- **What changes:** only the menu bar item's look. The badge keeps its shape and the count or words stay, all in the menu bar's ink, as with Status colors off. The panel and the widgets show everything as before.
- **When it ends:** when the verdict asks for more attention, by the ripple's rule (section 3.1): a worse mark, or more under the same mark. The color comes back with the ripple. It also ends when the verdict clears, so the next problem alerts afresh.
- **As it eases:** quiet follows the verdict down. Five incidents quieted that fall to two alert again at three.
- **While nothing current is known:** it holds. Offline is not worse.
- **How long:** for this launch only. Quiet is never saved and never sent anywhere.
- **Not offered** while there's no alert, or while Status colors are off.
- **Status card:** a Quiet button beside the verdict, pressed in the accent while quiet. In Terminal, a keycap line at the foot of the Status box: `m quiet the menu bar until it gets worse`, or `m menu bar quiet until it gets worse · undo`.
- **VoiceOver:** "Topophany: 5 incidents, quieted, updated 4 seconds ago."

## 4. The panel

The header shows the mark, the project and view, Open in Terminal (⌘O) and Settings (⌘,). The footer shows the connection and Quit. Sections run in this default order:

1. **Status.** Fixed, always first, pinned when the panel scrolls.
   - The verdict.
   - Every configured check by health, plus a legend. Native draws one tick per check while each tick can be told apart, up at about half strength so trouble stands out, and unknown hollow; past that, a stacked bar with unknown hatched.
   - The verdict's tile is flat and calm: a tint of its status color, edged in it, with the glyph in the color itself. Nothing on it shines or casts a shadow.
   - Observers live, and when the frame was updated.
   - Offline: a CACHED card with the last snapshot's verdict, and no bar.
2. **Seen from.** Observers that see a problem, worst first, then "*N* others report no problem". This answers "is it me or them?"
3. **Needs attention.** Open ledger incidents, then other entries ranked by `view.AttentionRank`. It shows 3 or 5 rows, then "*N* more in Topophany". The section is hidden when empty. Each row ends in its state word (OPEN, WARN), the word alone in its color: the row's mark already says the state, so it takes no chip. A route too long for its row is cut so both ends stay readable: an end that fits half the room keeps its width, and the other takes the rest.
4. **Applications.** One row per declared application: its health glyph, a dot per service, and a note.
5. **Fleet.** Every node `topo` lists (`servers.list`), by who runs it, two to a row with each provider's logo (section 4.1).
   - **Edges and platforms first,** each on its own and saying what it is: what stands in front of everything else. A hairline, then servers: a provider's together, where its first server is in `topo`'s list, and a node that names no provider on its own, by its name and kind.
   - **Marks:** one per node, `topo`'s. A group has no health of its own and is never tinted for its nodes; the app adds nothing up.
   - **Without `servers.list`:** the pinned servers' cards stand in. When the list isn't current, the names stay and every mark is withheld (◌).
6. **Servers.** Off by default. The Servers-tab card for each pinned node: CPU, memory and disk meters against the check's own limit, services, and age. Stale readings are withheld. Each card leads with its provider's logo (section 4.1).
7. **Time zones.** The local time where the servers are. See section 5.1.
8. **This Mac.** See section 5.

Size:

- **Native:** 344 pt wide, cards 6 pt apart. Rows that open something (attention entries, "*N* more") light faintly under the pointer, as far out as the keyboard's focus.
- **Terminal:** 48 columns of SF Mono 12 inside 7 pt margins.
- **Height:** never more than the screen minus the menu bar. Status stays pinned and the rest scrolls.

The Terminal theme draws each section as the TUI draws a panel:

- **Boxes:** a rounded box with its title set in the top border, and right-aligned metadata in the border as well.
- **The status box:** its border is tinted by the verdict.
- **Focus:** the focused row gets the TUI's selection background and accent bar, for keyboard use (↑↓, ↵).
- **The count:** the TUI's big 3×5 digits.
- **Meters:** colored by `loadColor`.
- **CPU history:** block sparks.
- **Footer:** keycaps for Open, Settings and Quit.

### 4.1 Providers

A node's provider is who runs it: a company that rents servers, or an edge or a platform that services are deployed to. `topo` sends it as the topology writes it, in the provider's own spelling where `topo` knows the provider.

- **Who:** the app knows the sixteen providers `topo` knows, by every name `topo` accepts, and more beyond them. A provider is matched with case and everything but letters and digits removed, so "Fly.io", "fly-io" and "flyio" are one. A known provider is written its own way.
- **Logos:** the ten that `topo` draws are its own outlines, from Nerd Fonts (Devicons, MIT; Linode's from Font Awesome, CC BY 4.0; Oracle's ring from Material Design Icons, Apache 2.0). Others come from Simple Icons (CC0). Each is its owner's trademark, shown only to say who runs a node. Wordmarks and hairline logos that turn to mush at panel sizes are left out.
- **Where:** a server card's tile, before its name. A provider without a logo gets its initials; a node without a provider, its kind's symbol.
- **Color:** in Native, a logo is drawn in the text's color. Brand colors would compete with health: an orange logo reads as warn, a green one as up, a red one as down. In Terminal, a logo takes its brand's color 12% toward the text, as the TUI draws it, and more where it would be too dark to read on the ink.
- **Meaning:** none. A logo never says how a node is doing.

`design/assets/providers.js` holds the names, colors and outlines. `scripts/make-providers.py` turns it into Swift, and the outlines into `provider-logos.js` for the previews, so both draw the same shapes.

## 5. This Mac

There are three modes: **Local readings**, **As a server** and **Off**.

### Local readings

The app reads these natively, every 2 s by default:

| Reading | Source | Shown |
|---|---|---|
| CPU | `host_processor_info` tick deltas | total, system, user; the last 60 samples as bars |
| Memory | `host_statistics64`, `kern.memorystatus_level` | used %, pressure; app / wired / compressed (as Activity Monitor) as parts of one bar |
| Storage | `volumeAvailableCapacityForImportantUsage` | used %, used of total |
| Network | `getifaddrs` counters on the primary interface (`NWPathMonitor`) | ↓ / ↑ rate on one mirrored chart (↓ above the line, ↑ below), interface and address |
| Battery | IOKit power sources | charge, state, time remaining (hidden on desktops) |

Local readings never pass through `topo`, and nothing runs `top`. The `topo` client process the app starts samples nothing from the host, and section 11.3 removes `top` from `topo`'s own host check as well.

### As a server

A `server.card` row for the chosen node: the card the Servers tab draws, read from the collector. It adds "From here", the verdict of the observer on that node. Settings suggests the node whose ID or name matches the Mac's `LocalHostName`. Without a host check on the node, resources read unknown.

### 5.1 Time zones

Servers sit in different places, and an incident at 3 AM in one place is 6 PM in another. This section shows the time where each server is, with that server's health.

- **Rows:** one per time zone, west to east. Each row holds the places `topo` names (`servers.list`'s `where`) that share the zone, and one mark per server in them, its health as `topo` sent it. This Mac's zone is always a row, marked by the location arrow and "here"; with no servers in it, the row is titled This Mac.
- **Each row shows:** the local time, the zone's short name, its offset from here ("+3h"), and "tomorrow" or "yesterday" when its date isn't this Mac's.
- **The day ribbon:** the zone's 24 hours, from 12 hours before now to 12 hours after, so every row's now lines up in one column, a fine tick in the accent. The band is thin: slate from 20:00 to 4:00, pale from 8:00 to 16:00, and soft between, with a gap at midnight. That is a clock's hour, not the sun's, and neither tone is a status color.
- **Where a zone comes from:**
  - A place's name suggests one: the system's city for every zone, in English, Japanese and Chinese, and the cities of `topo`'s gazetteer that no zone is named for (San Jose, Frankfurt, 成都). A label that only starts with a city counts ("Tokyo 2").
  - In Settings, Places… lets the user choose another zone for any place, or none.
  - Places without a zone (`anycast`, coordinates, unmatched names) are counted at the foot of the section: "2 without a time zone".
- **Health:** the marks are `topo`'s and nothing else. A zone row has no health of its own. When the list isn't current, the clocks go on and every mark is withheld (◌).
- **Without `servers.list`:** the pinned servers' cards stand in.
- **Server cards** (Servers, and This Mac as a server) add the time where the server is after its place, by the same zones. It never truncates; the provider gives way first. Widgets leave it out, because they redraw too seldom to keep a clock.
- **Widgets:** not offered; the section is the panel's.
- **Terminal:** two lines per zone. The ribbon is one cell per stretch of hours, in the palette's own night and day tones, and now is the accent.

## 6. Themes in v1

| Theme | Renderer | Tokens |
|---|---|---|
| **Native** | `cards` | System materials and colors. Glass, SF Pro, SF Symbols, system green, orange, red and gray, and the accent color for capacity. Light, dark or Match System. |
| **Aurora** | `cards` | Glass tinted the green-blue of a northern sky: accent `#2DD4BF` / `#0D9488`, a violet second accent, teal-tinted cards and fills. System status colors. Light or dark, as Native. |
| **Linen** | `cards` | Matte, warm cards set in New York: an ink-blue accent (`#9DB0E8` / `#34509A`), walnut or linen ground, more opaque than glass. System status colors. Light or dark, as Native. |
| **Terminal** | `cells` | The TUI's palette from `internal/tui/theme.go`: ink `#0A1016`, accent `#5EEAD4`, sky `#7DD3FC`, up `#4ADE80`, warn `#FBBF24`, down `#F87171`, unknown `#6B7A8C`, line `#243443`. It always paints its ink. |
| **Paper** | `cells` | The TUI printed on warm paper: ink `#F5F0E6`, text `#2A2925`, accent `#0F766E`, up `#15803D`, warn `#B8720A`, down `#B91C1C`, unknown `#87929B`. Always light. |
| **Dusk** | `cells` | The TUI at nightfall: ink `#1A1735`, text `#E6E2F8`, accent `#B4A7FA`, sky `#8BD3F7`, up `#6EE7B0`, warn `#F7B96B`, down `#F7768E`, unknown `#7A759F`. Always dark. |

The theme applies to the panel, the menu bar item and every widget. Settings shows each theme as a chip of its colors, in one line that scrolls when more than fit: its ground, then accent, second accent, up, warning, down and unknown, as the panel would draw it now. Each renderer says what those colors are (`Renderer.colors`). In Edit Widget, a widget can take any built-in theme, or the menu bar's.

## 7. Widgets

### 7.1 Kinds and sizes

Sizes in points sit on a 170 pt grid with 24 pt gaps. WidgetKit's own sizes vary with the display (on a 1920×1080 pt display, a 164 pt grid with 16 pt gaps), so renderers lay out each size in the bounds WidgetKit gives, never the table's.

| Kind | Small 170×170 | Medium 364×170 | Large 364×364 | Extra large 752×364 |
|---|---|---|---|---|
| **Status** | verdict, a mark per check, observers, age | Status, plus Needs attention (or Applications when nothing needs attention) | Status with legend, Seen from, Needs attention | Large, plus Applications and Fleet |
| **Server** | one node: CPU, memory and disk against limits, state, age | plus its services and what it observes from there | n/a | n/a |

- **A mark per check.** In a narrow column (the small widget, and the medium widget's left), the bar's ticks wrap into a grid: every check as its mark, filled a column at a time in the bar's order, so trouble gathers at the right as it does on the bar. Up is quieter than trouble. Past what can be read, the stacked bar.
- **Fleet.** The extra large widget shows as many groups as fit. The rest are counted in a last cell that keeps their nodes' marks, trouble first, so trouble left out still shows.

Every widget is built from the same section models and the same renderer as the panel, in the same theme. In the cells renderer they become the TUI's boxes at 11 pt. In **Edit Widget**, users choose what a widget shows (the medium widget's right side; the server, including This Mac) and its theme (default: the same as the bar). They never choose what it means. Clicking a widget opens the panel; clicking an attention row opens the TUI on it.

### 7.2 Data

A widget extension runs in its own process and can't attach to the app's pipe. The app is the only reader of `topo`. After each frame it keeps the latest frame and the theme in its App Group container, and asks WidgetKit to reload:

- **At once** when the verdict state changes, or a widget-visible row changes health.
- **On a heartbeat** of 30 min while nothing changes.

Local readings are not offered in widgets, because a widget can't refresh often enough to show them live.

### 7.3 Honesty

Each reload gives WidgetKit two timeline entries:

- **Now:** the current verdict.
- **Not current:** dated at the next heartbeat plus 15 min.

If the app quits, crashes or the Mac sleeps through a renewal, the widget switches itself to **Not current**. It shows the last verdict as history ("Last known: 5 incidents · 47 min ago"), never as now. The widget's age line uses WidgetKit's relative date, which counts up without reloads.

### 7.4 Rendering modes

macOS draws desktop widgets without background or color while another app is in front. Shape-first glyphs keep every state readable there. In that mode, the cells renderer drops its box borders for plain headings.

## 8. Theme architecture

Themes must be able to grow: more built-in themes, and user themes later. So a theme is split in two.

- **A renderer** is code, in `TopophanyThemes`. It lays out every section model for every surface (panel, status item, widget sizes). It owns the status glyph shapes and the meaning of each token slot. v1 has `cards` and `cells`. A new renderer (say, a gauge-heavy one) is a new type that conforms to the `Renderer` protocol, and every surface gets it at once.
- **A theme** is data: the renderer's name plus its tokens.

```json
{
  "schema": 1,
  "id": "paper",
  "name": "Paper",
  "renderer": "cells",
  "appearance": "light",
  "tokens": {
    "ink": "#F5F0E6", "inkHigh": "#ECE5D7", "selection": "#E4DDCC", "key": "#E3DBCA", "line": "#D3C9B5", "track": "#E6DFD0",
    "text": "#2A2925", "muted": "#6E695D", "faint": "#A29C8E", "glow": "#FFFFFF", "accent": "#0F766E", "accent2": "#1D4ED8",
    "kind": "#BE185D", "up": "#15803D", "warning": "#B8720A", "down": "#B91C1C", "unknown": "#87929B"
  },
  "font": { "family": "SF Mono", "size": 12 }
}
```

A `cards` theme that follows the system gives its slots per appearance. `dark` and `light` each override `tokens` in that appearance:

```json
{
  "schema": 1, "id": "aurora", "name": "Aurora", "renderer": "cards", "appearance": "system",
  "tokens": {},
  "dark":  { "accent": "#2DD4BF", "accent2": "#A78BFA", "panelMaterial": "rgba(12, 28, 34, .62)", "card": "rgba(45, 212, 191, .07)" },
  "light": { "accent": "#0D9488", "accent2": "#7C3AED", "panelMaterial": "rgba(236, 253, 248, .62)", "card": "rgba(240, 253, 250, .7)" },
  "font": { "family": "SF Pro", "size": 13 }
}
```

- **Token slots:**
  - `cells` takes the slots above.
  - `cards` takes `accent`, `accent2`, `card`, `cardEdge`, `panelMaterial`, `fill`, `fill2`, and optionally the status colors. Missing slots fall back to the system's. When it follows the system, `dark` and `light` may give any slot per appearance.
- **Type:** `font.family` is SF Pro, SF Pro Rounded or New York for `cards`, which draws SF Pro for any other. `cells` always draws SF Mono, which its grid is measured in. The size is the renderer's, scaled by the Text size setting.
- **Validation:** a theme is refused, with the reason, unless all of these hold:
  - text on ink is at least 4.5:1;
  - every pair of status colors differs by at least ΔE 15 (OKLab ×100) to normal vision, in each appearance it draws in. Under simulated color-blindness, pairs under ΔE 8 are reported as advisories: no green, orange and red palette keeps that margin, and every status has its own shape;
  - every required slot is present;
  - only a `cards` theme that follows the system gives `dark` and `light` sets.
- **What a theme can't change:** glyphs, layout and meaning.
- **Where themes live:**
  - Built-in themes are compiled in.
  - User themes will be read from `~/Library/Application Support/topophany-bar/Themes/*.json`, then validated and copied into the App Group so widgets draw them too.
  - v1 ships the loader disabled, but every built-in theme goes through the same `Theme` type and validator, so the path is already exercised.
- **Swift types:** `Theme { id, renderer: RendererID, tokens: Tokens }`. `Renderer` is a protocol with `panel(_:)`, `statusItem(_:)` and `widget(_:family:)`, each taking section models and tokens.

**Aurora** and **Linen** (`cards`) and **Paper** and **Dusk** (`cells`) are built in, and each is only a token set: proof that a token file is a whole theme.

## 9. Configuration

**You choose what to look at, never what it means.**

| Yours (Settings, Edit Widget) | Fixed (topology + collector) |
|---|---|
| Theme; panel appearance; text size | What counts as up, warn, down or unknown |
| Menu bar: Symbol, Count or Words; status colors; motion; this Mac's readings; quiet its alert until it gets worse | Thresholds (`max_cpu_percent` and others, in `topology.json`) |
| Sections on or off and their order (Status is fixed) | Freshness, staleness, publisher lease |
| The time zone of each place | Each server's health in Time zones |
| Attention rows (3 or 5); which applications; pinned servers | How groups add up (unknown always counted) |
| What each widget shows and its theme | Status glyphs and their meaning |
| This Mac mode, readings, volume, interface, sample rate | No expressions or formulas |
| `topo` path, profile, observer view, refresh (1 s to 1 h); open at login; terminal for the TUI; language (system, English, Japanese, Simplified Chinese) | |

Settings live in `~/Library/Application Support/topophany-bar/settings.json`. On every change the app compiles them into a `topo` monitor template and sends it to the running engine.

```json
{
  "schema": 1,
  "topo": { "path": "/opt/homebrew/bin/topo", "profile": "home", "observer": "", "interval": "5s" },
  "appearance": { "theme": "native", "panel": "system",
                  "menuBar": { "show": "count", "statusColors": true, "motion": true, "readings": [] } },
  "sections": [
    { "id": "status" },
    { "id": "seen" },
    { "id": "attention", "limit": 3 },
    { "id": "applications", "only": [] },
    { "id": "fleet", "enabled": true },
    { "id": "servers", "enabled": false, "nodes": ["oracle-ny", "bwh-la"] },
    { "id": "zones", "enabled": true, "places": { "Seattle": "America/Los_Angeles" } },
    { "id": "mac", "mode": "local", "readings": ["cpu", "memory", "storage", "network", "battery"], "every": "2s" }
  ],
  "openAtLogin": true,
  "terminal": "com.mitchellh.ghostty",
  "language": "system"
}
```

## 10. Architecture

```
topophany-bar.app ──stdin: request──▶ topo monitor stream ──TLS, saved profile──▶ topo serve
     │  ▲ ◀──stdout: frames───────────┘                    ◀──/v1/snapshot────────┘
     │  └── reads macOS for This Mac (local readings)
     └──▶ App Group: latest frame + theme ──▶ widget extension (WidgetKit timeline)
```

### 10.1 Packages

Everything except the app shell is AppKit-free: SwiftUI and Foundation only, so it builds for any Apple platform.

```
topophany-bar/
  Package.swift
  Sources/
    TopophanyKit/       Frame and Row models, FrameDecoder, ReaderPolicy (deadlines), Request and TemplateCompiler,
                        Settings, Engine protocol
    TopophanyEngine/    ProcessEngine; later EmbeddedEngine
    TopophanySections/  one model per section, built from frames: Status, SeenFrom, Attention, Applications,
                        Fleet, ServerCard, Zones, Local; PlaceZones (a place's suggested time zone);
                        Provider (who runs a node, by any of its names)
    TopophanyThemes/    Theme, Tokens, ThemeStore, ThemeValidator, Renderer protocol;
                        Cards/ (SwiftUI) and Cells/ (CellCanvas)
    TopophanyWidgets/   TimelineProvider (current and not-current entries), widget views per family
    LocalReadings/      Sampler protocol; Mach and IOKit samplers
  Apps/
    topophany-bar/      the macOS shell: StatusItemController, PanelController (NSPanel), Settings window
    Widgets/            the widget extension: a thin wrapper around TopophanyWidgets
  Tests/                frame goldens from `topo preview`, deadline rules, template compiler, theme validator,
                        snapshot images of every section, size and theme
```

Rules:

- Only `Apps/` imports AppKit.
- Renderers take section models, never frames.
- Engines produce frames, never views.
- **`CellCanvas`** draws any grid of styled cells together with the TUI's vector pieces (boxes, half-block pixels, blocks), crisply at any scale. The `cells` renderer is built on it, and it can draw other cell-based screens too.

### 10.2 Engines

```swift
protocol Engine {
    func start(_ request: Request) -> AsyncThrowingStream<Frame, Error>
    func update(_ request: Request) async throws
}
```

- **ProcessEngine** (v1) runs `topo monitor stream` as a child process with pipes.
  1. **Finding `topo`:** the path setting, then the login shell's `PATH`, then `/opt/homebrew/bin` and `/usr/local/bin`.
  2. **Version check:** run `topo version`; if `topo` is too old to have `monitor stream`, offer the upgrade command.
  3. **When the engine stops:** restart it after 1, 2, 4 … up to 30 s, and show ◌ until the next frame.
  4. **When the app quits:** stdin closes and `topo` exits.

  Spawning a user-installed binary rules out the App Sandbox, so v1 is distributed with a Developer ID, notarized, as a Homebrew cask.
- **EmbeddedEngine** (later) links `libtopo`: the Go `monitor stream` core built with `-buildmode=c-archive` into an XCFramework. It exposes `topo_stream_start(request, callback)`, `topo_stream_update` and `topo_stream_stop`, and speaks the same request and frame JSON. This is for builds that can't start a process. Only that library build uses cgo, for its C exports; the `topo` binary stays CGO-free with zero modules.

### 10.3 Protocol

The exact contract is [`docs/PROTOCOL.md`](../docs/PROTOCOL.md), which wins wherever it differs from this summary.

**Request (stdin).** One JSON object per line. A new line atomically replaces the running request, so settings apply without a restart. An invalid line leaves the previous request running and produces a frame with `lifecycle: "error"`.

```json
{"schema":1,"profile":"home","observer":"","interval":"5s",
 "template":{"schema":1,"title":"Topophany","bar":{"row":"status"},"rows":[
  {"id":"status","metric":"summary.verdict"},
  {"id":"seen","metric":"observers.verdicts","visual":"list"},
  {"id":"attention","metric":"attention.list","visual":"list","limit":3},
  {"id":"apps","metric":"applications.list","visual":"list"},
  {"id":"mac","metric":"server.card","select":{"node":"macbook"}}]}}
```

**Frames (stdout).** The existing panel output schema 1, one object per line, at most 1 MiB:

- **Frame fields:** `name`, `instance`, `sequence`, `lifecycle` (`running`, `error` or `stopped`), `generated_at`, `publisher_expires_at`.
- **Row fields:** `value`, `text`, `health`, `freshness`, `reason`, `sampled_at`, `valid_until`.
- **When frames are sent:** on change, on any health, freshness or lifecycle transition, and at least every 10 s to renew the 30 s lease.

The reader rules are those of `topo monitor preview`, and they live in `TopophanyKit.ReaderPolicy`:

- Every second, check the lease and each row's deadline against the clock.
- Treat implausibly future timestamps as unavailable.
- Never extend a row because its lease was renewed.

## 11. Changes in `topo`

The value shapes, error codes and the `preview` source are specified in [`docs/PROTOCOL.md`](../docs/PROTOCOL.md).

### 11.1 `topo monitor stream`

The `monitor` core moves into a package with a function API: requests in, frames out. Two thin wrappers sit on top of it:

- the CLI subcommand, over stdin and stdout;
- later, `libtopo`, over C callbacks.

### 11.2 Metrics

Each is computed from `internal/view`, so the bar and the TUI agree.

| Metric | Visual | Value |
|---|---|---|
| `summary.verdict` | `status` | `{state, glyph, text, counts, incidents, observers}` from `View.Verdict`, `Counts`, `Live`. It is separate from `summary.status`, so existing templates keep working. |
| `observers.verdicts` | `list` | per observer: `id`, `name`, `health`, counts, `live`, `last_seen` |
| `attention.list` | `list` + `limit` | open ledger records, then `NeedsAttention` rows by `AttentionRank`, plus `more` |
| `applications.list` | `list` | per application: `id`, `name`, `health`, services, attention and unmonitored counts |
| `server.card` | `card`, `select.node` | from `Fleet().Card`: resources against limits, services, `observes` |

### 11.3 macOS host check without `top`

Today `sampleDarwinRuntime` (`internal/probe/host_macos_parse.go`) runs four commands on every host check:

- `top -l 2 -s 1`, which costs a full second and a process;
- `sysctl -n hw.memsize`;
- `vm_stat`;
- `ps -axo`.

The Windows sampler already reads counters in-process through `syscall`. On macOS the same is possible without CGO, by calling libSystem through assembly trampolines: the mechanism the standard library and `golang.org/x/sys/unix` use on darwin, written in-tree to keep zero modules.

| Fact | Now | In-process |
|---|---|---|
| CPU | `top`, second sample (1 s) | `host_statistics(HOST_CPU_LOAD_INFO)` tick deltas over 200 ms, like Linux; `cpu_sample_ms` becomes 200 |
| Memory total | `sysctl -n hw.memsize` | `syscall.Sysctl("hw.memsize")` |
| Memory available | `vm_stat` free + inactive + speculative | `host_statistics64(HOST_VM_INFO64)`, same three counters, so `memory_basis` and every recorded fact keep their meaning |
| Processes | `ps -axo pid,stat,rss,comm` | `sysctl` `kern.proc.all` for count, zombies and `p_comm`; `proc_pidinfo(PROC_PIDTASKINFO)` for RSS of the selected name only |

How the change is tested and kept safe:

- **Contracts:** unaffected, because a contract covers what is measured, not how.
- **Failure:** a failing call reports a monitor error, exactly as a failing command does now.
- **Tests:** the existing fixture tests become tests of struct decoding, plus a darwin-only integration test that compares against `vm_stat` and `ps` once.
- **The app's local readings:** these remain the app's own, Activity Monitor-style; the two never need to agree, because only `topo`'s are evidence.

## 12. Phases

1. **`topo`:**
   - the `monitor stream` package and subcommand, the five metrics, and the `list` and `card` visuals, with golden tests over `topo preview` scenarios;
   - the macOS host check without commands.
2. **App core:** `TopophanyKit`, ProcessEngine, ReaderPolicy, the status item, and the `cards` renderer with Status, Seen from and Needs attention.
3. **App complete:**
   - Applications, Servers and This Mac in both modes;
   - the `cells` renderer on `CellCanvas`;
   - Settings, and the theme store with the built-in themes.
4. **Widgets:** Status in four sizes, Server in two, the App Group hand-off and the not-current timeline.
5. **Polish:** VoiceOver, Reduce Transparency and Increase Contrast, keyboard navigation, localization (en, ja, zh), signing, notarization and the cask.

Later: user theme files, EmbeddedEngine and `libtopo`, more renderers.

## 13. Open questions

- Should Seen from collapse to counts beyond about 20 observers?
- Should the Terminal theme follow the user's terminal font when one is set?
- What should the widget heartbeat be: 30 min, or tuned to the observed reload budget?
