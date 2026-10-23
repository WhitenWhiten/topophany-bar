# topophany-bar: design notes (v1)

A native macOS menu bar app and desktop widgets for `topo`. Draft of 2026-10-18.

- **Repository and product name:** `topophany-bar`.
- **Minimum system:** macOS 26. Tested on macOS 27.

The HTML previews next to this file show the design:

| Page | What it shows |
|---|---|
| `index.html` | overview, the three looks, widgets, themes, architecture |
| `playground.html` | every state, theme and setting, live, pinned services included |
| `states.html` | the status item and status card in all five states |
| `widgets.html` | four sizes, both themes, every state, monochrome rendering; the Service widget |
| `settings.html` | the Settings window |

## 1. Goal

**At a glance, what does the collector conclude right now?** The menu bar item answers that, and it moves only while the answer is current. One click opens a panel that says where the problem is, which vantage points see it, what is affected, and how this Mac is doing. Widgets pin the same cards to the desktop.

Out of scope for v1:

- local notifications (collector webhooks already alert)
- RunCat or any file output (the stream replaces them)
- loading user theme files (the format is designed in section 8)
- the embedded engine (section 10.2)
- history charts beyond the local sparklines and a service card's recent samples (section 4.2)
- Windows and Linux

## 2. Principles

1. **Shows, never decides.** Every state, count and health comes from `topo`, computed by `internal/view` exactly as the TUI computes it. The app sets no thresholds and infers no fault.
2. **Blind is a state.** Freshness is separate from health. Past the publisher's lease or a row's `valid_until`, the row is withheld and the item turns ◌. Widgets get the same rule through their timeline (section 7.3). An old green never stays on screen.
3. **Shape, then color.** Every status mark changes shape (● ▲ ✕ ○ ◌) as well as color. Shapes belong to the renderer, so no theme can remove that distinction.
4. **Unknown is never zero.** Bars and ratios keep unknown in the denominator, drawn hollow or hatched. Unknown numbers are `null`.
5. **Local is not evidence.** This Mac's local readings carry no health, are labeled "local readings", and never leave the Mac.
6. **Beauty through restraint.** The panel is calm when things are calm: color appears only where something needs a look. In the cards themes, up among other marks (the bar's ticks, a legend, a list's dots) is drawn at about half strength, so trouble stands out; a verdict keeps its full color. A legend's count of none takes no color at all, as in the TUI: its shape says which it is.

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
- **Right-click menu:** About Topophany; Quiet Until It Gets Worse (section 3.3); Open in Terminal; Settings…; Quit Topophany.
- **About:** the standard panel: the version, and four short lines of credits. They link to Topophany, with the version of the `topo` running; to this app's source, license and acknowledgements, in one line; and to Topophany again, inviting a star. In the copyright below them, the author's name links to their homepage, whiten.dev.
- **While a window is open:** Settings or About brings the app forward, with a Dock icon and a menu bar: About, Settings… (⌘,), Hide and Quit (⌘Q); Close (⌘W); and Edit's undo, cut, copy, paste and select all for the fields. When the last one closes, the app is back in the menu bar alone.

### 3.1 Motion

Settings › Appearance › Menu bar icon offers the default renderer, the built-in
DeepSeek Girl, White Night Sky, and imported icons. White Night Sky adapts the
personal homepage's Bayer 8×8 sky, layered value-noise clouds, shaded disk and
paper-white horizon to a 3.25:1 panorama. Its 180 cached frames follow a closed
path through the noise field over 24 seconds; the native layer loops them under
the same motion policy as other icons. They are drawn for the pixels the item
has, one dot to a pixel at every size and scale, and the last two heights in use
are kept. At 26 pt it occupies an 80 pt slot.
DeepSeek Girl uses the approved portrait and a
matching blink frame: a 140 ms blink every 4.8 seconds, with a quarter-point
breathing movement. Shared transparent margins are trimmed, leaving the full
headband and hair visible. Its status badge sits beside the portrait.

An icon can show the status itself, and then no badge sits beside it; the count
or words still do. White Night's disk is a moon, drawn still over the moving sky:

| Status | The moon | In ink (quiet, or status colors off) |
|---|---|---|
| clear | full and bright, as the homepage's disk | the same |
| degraded | in partial eclipse, its shadow amber, a rim on its lit side | the shadow in ink, ◑ |
| down | a blood moon, the printed sky beside it reddening | dark throughout |
| unknown | its outline alone, clouds passing within | the same |
| offline | its outline in dashes | the same |

Each is its own shape, as the badges are, so without color it says the same. A
change dissolves the old moon into the new through the Bayer matrix's own order,
in about half a second, while the sky plays on; with motion off it changes at once.

Import accepts PNG/JPEG still images, GIF/APNG animations with their frame timing,
or multiple equally sized PNG frames, sorted naturally by filename at 12 fps, or a
folder of them. Files or folders named for a status make a status pack that shows
the status itself: `clear`, `warning`, `error`, `unknown` and `offline` (also `up`,
`degraded`, `down`, `正常`, `警告`, `故障`, `エラー` and the like), as `clear.gif`,
`error-01.png` or `warning/`. A pack needs clear's frames; every file in it is
named for one status, and all its frames share one size and the import's limits.
Each status plays its own frames, and a change fades between them. A status the
pack lacks plays clear's frames without their color, beside the badge, so they
don't say all is well; quiet or with status colors off, an alert's frames lose
their color too.
Imports are normalized to small PNG frames in `MenuBarIcons/<UUID>` beside the
settings file; the original files are never changed and may subsequently be
moved. The settings keep only the selected ID, size (18, 22 or 26 pt), and speed.
The library supports rename and delete, with the default icon used if a selected
asset is unavailable. Input limits are 32 MB total, 4096 pixels per dimension and
180 frames. Frame delays are bounded to 20 ms–10 s. Normalized frames retain up
to 384 pixels on the longest side for wide Retina artwork. Icon slots support
aspect ratios through 6:1; wider images fit proportionally inside that slot.

Portraits play on their own native layer using their frame durations, leaving the
readings and status rendering independent. They animate only with current data
and the existing motion policy permits it; sleeping or hidden displays, Reduce
Motion and Low Power Mode show the first frame. The selected size is capped to
fit the actual menu bar. Changing readings does not restart an animation.

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

The header shows the mark, the project and view, Open in Terminal (⌘O) and Settings (⌘,). The footer shows the connection and Quit, and while the panel scrolls, the quick scroll.

Settings › General › Keyboard shortcut records a global key to toggle the panel from any app. No key is assigned by default. Include Command, Control or Option; Esc cancels recording, Tab leaves the recorder, and Clear removes the shortcut. Recording pauses the saved shortcut and resumes it on cancellation. A conflict leaves the saved choice intact: enabled macOS symbolic shortcuts, Topophany's reserved commands and existing global hotkey registrations are checked. Other apps' internal shortcuts and event taps cannot all be detected. macOS can keep protected system combinations active during recording. A saved shortcut that cannot be registered on launch shows its error in General. The registration is checked again when Settings becomes key.

Sections run in this default order:

1. **Status.** Fixed, always first, pinned when the panel scrolls.
   - The verdict.
   - Every configured check by health, plus a legend. Native draws one tick per check while each tick can be told apart, up at about half strength so trouble stands out, and unknown hollow; past that, a stacked bar with unknown hatched.
   - The verdict's tile is flat and calm: a tint of its status color, edged in it, with the glyph in the color itself. Nothing on it shines or casts a shadow.
   - Observers live, and when the frame was updated.
   - Offline: a CACHED card with the last snapshot's verdict, and no bar.
   - While no `topo` can run (none found, or one too old): Download topo beside the verdict, in the accent (`d` in Terminal). It says how far the download has got, and why one failed (section 10.2.1).
2. **Seen from.** Observers that see a problem, worst first, then "*N* others report no problem". This answers "is it me or them?"
3. **Needs attention.** Open ledger incidents, then other entries ranked by `view.AttentionRank`. It shows 3 or 5 rows, then "*N* more in Topophany". The section is hidden when empty. Each row ends in its state word (OPEN, WARN), the word alone in its color: the row's mark already says the state, so it takes no chip. A route too long for its row is cut so both ends stay readable: an end that fits half the room keeps its width, and the other takes the rest.
4. **Map.** Where the nodes are and what joins them, as the TUI's geo map draws it. See section 4.3.
5. **Applications.** One row per declared application: its health glyph, a dot per service, and a note.
6. **Services.** Off by default. The card of each pinned service: the observers that see it, how fast it answered them lately and how much of the day it was up. See section 4.2.
7. **Fleet.** Every node `topo` lists (`servers.list`), by who runs it, two to a row with each provider's logo (section 4.1).
   - **Edges and platforms first,** each on its own and saying what it is: what stands in front of everything else. A hairline, then servers: a provider's together, where its first server is in `topo`'s list, and a node that names no provider on its own, by its name and kind.
   - **Marks:** one per node, `topo`'s. A group has no health of its own and is never tinted for its nodes; the app adds nothing up.
   - **Without `servers.list`:** the pinned servers' cards stand in. When the list isn't current, the names stay and every mark is withheld (◌).
8. **Servers.** Off by default. The Servers-tab card for each pinned node: CPU, memory and disk meters against the check's own limit, services, and age. Stale readings are withheld. Each card leads with its provider's logo (section 4.1). As in Terminal, its pill sits beside its name and its age beside where it is; that line fits as Terminal's does, the provider giving way first, then the place shortening, while the kind and the time stay. A foot says its services when it has any.
9. **Time zones.** The local time where the servers are. See section 5.1.
10. **This Mac.** See section 5.

Size:

- **Native:** 344 pt wide, cards 6 pt apart. Rows that open something (attention entries, "*N* more") light faintly under the pointer, as far out as the keyboard's focus.
- **Terminal:** 48 columns of SF Mono 12 inside 7 pt margins.
- **Height:** as tall as its content, up to the height the user leaves it at, and never more than the screen minus the menu bar. Status stays pinned and the rest scrolls, with no scroll bar, following the keyboard's focus as little as it must. Unpinned, Status scrolls with the rest. In Native, where more lies beyond the scroll's top or bottom, the rows fade into the panel there.
- **Choosing the height:** drag the panel's bottom edge, as a window's; the height is saved when the drag ends. Double-clicking the edge, or Reset in Settings, gives the screen's height back. The panel is never made shorter than its header, Status and footer with This Mac's four readings and two time zones between, as the theme and text size draw them, whatever the panel shows.
- **Quick scroll:** while the panel scrolls, a chevron beside Quit leaps about half the panel down, never further than the scroll shows at once, so no row passes unseen. At the end it points up and goes back to the top. Space does the same, unless a button has the keyboard (Full Keyboard Access), when Space presses that button.

Motion in the panel is quiet, and says only what happened:

- **Opening:** the panel fades in over a fifth of a second as it settles 4 pt down from the menu bar, and fades out quicker than it came.
- **Highlights:** under the pointer or the keyboard, a highlight fades in quickly and out a little slower, as a menu's does. A pressed button dims while held. Nothing bounces or shines.
- **A new frame:** numbers roll to their new value, meters ease to it and the verdict's tile settles into its new color.
- **Reduce Motion:** nothing slides or glides; fades stay.

The Terminal theme draws each section as the TUI draws a panel:

- **Boxes:** a rounded box with its title set in the top border, and right-aligned metadata in the border as well.
- **The status box:** its border is tinted by the verdict.
- **Focus:** the focused row gets the TUI's selection background and accent bar, for keyboard use (↑↓, ↵).
- **The count:** the TUI's big 3×5 digits.
- **Meters:** colored by `loadColor`.
- **CPU history:** block sparks.
- **Footer:** keycaps for Open, Settings and Quit, and while the panel scrolls, `␣ ↓` for the quick scroll (`␣ ↑` at the end).

### 4.1 Providers

A node's provider is who runs it: a company that rents servers, or an edge or a platform that services are deployed to. `topo` sends it as the topology writes it, in the provider's own spelling where `topo` knows the provider.

- **Who:** the app knows the sixteen providers `topo` knows, by every name `topo` accepts, and about seventy beyond them: clouds, VPS hosts, edges and platforms. A provider is matched with case and everything but letters and digits removed, so "Fly.io", "fly-io" and "flyio" are one. A known provider is written its own way.
- **Places:** "Home" (or "homelab") and "Office" (or "on-prem") are known as places, not companies. They take a glyph of the app's own, a house or a building, and keep the topology's spelling.
- **Logos:** the ten that `topo` draws are its own outlines, from Nerd Fonts (Devicons, MIT; Linode's from Font Awesome, CC BY 4.0; Oracle's ring from Material Design Icons, Apache 2.0). Others come from Simple Icons (CC0). Each is its owner's trademark, shown only to say who runs a node. Left out: wordmarks and hairline logos that turn to mush at panel sizes, and logos that are a ring or a cross, which would read as a status mark.
- **Where:** a server card's tile, before its name. A provider without a logo, or one the app doesn't know, gets its node's kind's glyph: a server, an edge's cloud, a platform's stack. These are drawn as lines, as a symbol is, so they never pass for a brand. A node without a provider gets its kind's symbol.
- **Color:** in Native, a logo is drawn in the text's color. Brand colors would compete with health: an orange logo reads as warn, a green one as up, a red one as down. In Terminal, a logo takes its brand's color 12% toward the text, as the TUI draws it, and more where it would be too dark to read on the ink.
- **Meaning:** none. A logo never says how a node is doing.

`design/assets/providers.js` holds the names, colors, outlines and glyphs. `scripts/make-providers.py` turns it into Swift, and the outlines into `provider-logos.js` for the previews, so both draw the same shapes.

### 4.2 Service cards

A pinned service's card is one family with the Server card: the same head, pill and foot, and in place of CPU, memory and disk, the observers that see the service. `topo` sends it as a `service.card` row, built from the card the Services tab draws; the app adds nothing to it. `design/assets/service.js` draws it in the previews.

- **Head:** the tile of the node it runs on (its provider's logo, section 4.1), its name, and its application and host: "Proxy chain · on BandwagonHost LA". The pill beside the name says its state: UP, WARN, DOWN, UNKNOWN, AFFECTED or CACHED.
- **Seen from:** a row per observer, in `topo`'s order (worst first), at most three: a mark per check, the observer's place (its name where two share a place), the worst check's recent samples, its median latency over the day (p50) and the day's share up (24h). A row per observer rather than per check, so two paths from one place never read as duplicate rows, and a path that fails beside one that passes stays in sight.
- **Recent samples:** the one history chart beyond This Mac's sparklines, because it says when something broke. Native: a passing sample rises from a baseline as tall as it took, against the slowest shown, in the accent at half strength; a failure hangs below the line in its color (down, warning for a policy failure, gray otherwise), so trouble differs in place as well as color. No sample, no mark. Terminal: the TUI's blocks, `▁` to `▇` and never a full cell so rows stay apart, in the palette's meter (Paper's hairlines, Dusk's braille); `✖ ▲ ○` for failures and `·` where none was taken, on the track.
- **Foot:** how many checks and how many fail, the edge in front by its logo and the colos it answered from (`☁ SJC · FRA`), and the age. Terminal: what it depends on (`→`) and the edge (`⇠`).
- **Honesty:** each check keeps its own deadline (`docs/PROTOCOL.md` §5). Past it, the check's mark turns unknown and its numbers go, its samples hatched, while the rest of the card stays. While `topo` holds no samples for a check yet, none are drawn. Not monitored, and not in the topology, say so.
- **Choosing:** Settings › Sections › Services › Choose…: every service `topo` lists (`services.list`), under its application. Nothing is pinned until you pin it. A `topo` without `service.card` draws everything else, and Settings says why the section is empty.

### 4.3 The map

The map draws `topo`'s `map.graph`: the nodes `View.Graph()` places, the lines between them, and each one's signal, as the TUI's maps draw them. The app only places them. It never infers a line, a health or a route.

- **Geographic map.** Each place appears where it is. Settings › Sections › Map chooses whether to fit every place or show the whole world.
- **Framing.** **Fit**, the default, frames every place as the TUI's fit mode does: the smallest arc of longitude holding them, its horizontal scale cos(latitude) so a mid-latitude network keeps its shape, and any gap over 60° folded to a narrow seam headed by the degrees it holds (`53°`), so an ocean doesn't take the width from the places. **World** shows the whole world once, centred on them. Antarctica is left out unless a node is there.
- **What it says.** In the panel and the small and medium widgets, places only: "Seattle", "San Jose · Los Angeles" where two would sit on one another, "Tokyo +2" where room is short. A place takes the mark of its worst node. The large and extra large widgets have room for more, and name each node beside its place. Never a full list of services or servers.
- **Lines.** An arc bowed north between two places, in the color of its signal: up a quiet green, carried fainter, affected and degraded the warning color, down red, unknown or withheld dotted gray. A declared link is solid and a hop a path implies dashed. A path hop shows when it needs a look, or when it's the viewing observer's own; containment never. Worse lines are drawn last, on top.
- **Dither.** Land is a field of dots on an 8×8 ordered (Bayer) dither, in the theme's ink: brighter near the places, fading toward the edges. The dots keep to the map as it moves. In Terminal, land is shaded cell by cell under a lattice of braille dots with a dotted coast, as the TUI draws it, and the places, arcs and names are the TUI's.
- **Magnifying.** In the panel, the scroll wheel (or a pinch) zooms about the pointer, up to 8×, and a drag moves the magnified map; a trackpad's sideways scroll moves it too. A scroll that began away from the map keeps scrolling the panel, and at the map's framing a scroll that would zoom out scrolls the panel, so the panel still scrolls past the map. Click the map, or reach it with ↑↓ and press ↵, to select it: ↑ zooms in, ↓ out, Esc lets it go. Double-click, or the zoom chip (`2.5×`), goes back to the framing. Merged places come apart as they're magnified. The panel opens framed every time.
- **Without a location.** Counted beneath the map with their marks, trouble first ("4 without a location ○ ○ ● ●").
- **Honesty.** Each mark and line is `topo`'s signal, never the app's. When the row lapses, the last graph stays as history with every mark withheld (◌), every line gray and the paths gone, "not current" beneath. A graph too large for `topo` to send says so.
- **Without `map.graph`.** An older `topo`: the places `servers.list` names (else the pinned servers'), placed where their names say (`topo`'s gazetteer, then the city a time zone is named for), with each server's mark and no lines, "placed by name" beneath. A place the app can't find is counted as without a location. Settings says why.

`Sources/TopophanyThemes/Map/` holds the layout both renderers share (`GeoView`, the TUI's framing; `GeoScene`, its sites and arcs), and `Resources/land.bin` the land: Natural Earth 1:110m, a 720×360 bit mask, the same as `design/assets/land.bin`.

## 5. This Mac

There are three modes: **Local readings**, **As a server** and **Off**.

The Apple logo identifies This Mac in Settings, Native cards and its Server widget.

### Local readings

The app reads these natively, every 2 s by default:

| Reading | Source | Shown |
|---|---|---|
| CPU | `host_processor_info` tick deltas | total, system, user; the last 60 samples as bars |
| Memory | `host_statistics64`, `kern.memorystatus_level` | used %, pressure; app / wired / compressed (as Activity Monitor) as parts of one bar |
| Storage | `volumeAvailableCapacityForImportantUsage` | used %, used of total |
| Network | `getifaddrs` counters on the primary interface (`NWPathMonitor`) | ↓ / ↑ rate on one mirrored chart (↓ above the line, ↑ below) over the same 60 samples as the CPU's bars, interface and address |
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
- **Server cards** (Servers, and This Mac as a server) add the time where the server is after its place, by the same zones. It never truncates; the provider gives way first. The Server widget leaves it out; the Time zones widget keeps the clocks.
- **The widget:** Time zones, small, medium and large (section 7.1), shows the section whether the panel does or not. Its clocks are plain text, set by an entry each minute: a widget keeps another zone's time live only as a timer with its seconds, and a timer clipped to its minutes isn't drawn at all. Its drawing is shapes and fills only: a layer clipped inside a canvas doesn't survive a widget's archive. As many zones as fit are drawn, This Mac's always among them, and the rest are counted at the foot ("+2 more") with their servers' marks, trouble first.
- **Terminal:** two lines per zone. The ribbon is one cell per stretch of hours, in the palette's own night and day tones, and now is the accent.

## 6. Themes in v1

Each theme looks its own, not only in its colors: its style (section 8) chooses its surface, how its sections are edged, the texture of its meters, and its grain.

| Theme | Renderer | Style | Tokens |
|---|---|---|---|
| **Native** | `cards` | Glass cards. Meters of fine graduated ticks. | System materials and colors. Glass, SF Pro, SF Symbols, system green, orange, red and gray, and the accent color for capacity. Light, dark or Match System. |
| **Aurora** | `cards` | A northern sky at night: an opaque ground deepening from teal to violet (mint to lavender in light), hairline-outlined cards, round shapes (a disc for the verdict, chips round at the ends), meters as a matrix of dots, SF Pro Rounded. | Accent `#2DD4BF` / `#0D9488`, a violet second accent, teal-edged cards and fills. System status colors. Light or dark, as Native. |
| **Linen** | `cards` | A matte page with a fine weave, set in New York: sections ruled rather than carded, titled in letterspaced small capitals, crisp corners, meters as a scale with its graduations and the limit a notch. | An ink-blue accent (`#A9B8EA` / `#34509A`), walnut or linen ground. System status colors. Light or dark, as Native. |
| **Terminal** | `cells` | The TUI's rounded boxes. Meters of solid cells, a hairline apart. | The TUI's palette from `internal/tui/theme.go`: ink `#0A1016`, accent `#5EEAD4`, sky `#7DD3FC`, up `#4ADE80`, warn `#FBBF24`, down `#F87171`, unknown `#6B7A8C`, line `#243443`. It always paints its ink. |
| **Paper** | `cells` | The TUI printed: paper grain, a masthead over a double rule, a rule over each section instead of a box, meters as a halftone on a dotted track, history drawn as a pen's hairlines. | Ink `#F5F0E6`, text `#2A2925`, accent `#0F766E`, up `#15803D`, warn `#B8720A`, down `#B91C1C`, unknown `#87929B`. Always light. |
| **Dusk** | `cells` | The TUI at nightfall: each section held by its four corners, meters and history in braille dots. | Ink `#1A1735`, text `#E6E2F8`, accent `#B4A7FA`, sky `#8BD3F7`, up `#6EE7B0`, warn `#F7B96B`, down `#F7768E`, unknown `#7A759F`. Always dark. |

Meters never shine: no gloss, no gradient lit from above. A reading past its check's limit reads in the warning color, and unknown is hatched (or a dashed rule), never empty.

The theme applies to the panel, the menu bar item and every widget. Settings shows each theme as a chip of its colors, in one line that scrolls when more than fit: its ground, then accent, second accent, up, warning, down and unknown, as the panel would draw it now. Each renderer says what those colors are (`Renderer.colors`). In Edit Widget, a widget can take any built-in theme, or the menu bar's.

## 7. Widgets

### 7.1 Kinds and sizes

Sizes in points sit on a 170 pt grid with 24 pt gaps. WidgetKit's own sizes vary with the display (on a 1920×1080 pt display, a 164 pt grid with 16 pt gaps), so renderers lay out each size in the bounds WidgetKit gives, never the table's.

| Kind | Small 170×170 | Medium 364×170 | Large 364×364 | Extra large 752×364 |
|---|---|---|---|---|
| **Status** | verdict, a mark per check, observers, age | Status, plus Needs attention (or Applications when nothing needs attention) | Status with legend, Seen from, Needs attention | Large, plus Applications and Fleet |
| **Server** | one node: CPU, memory and disk against limits, state, age | plus its services and what it observes from there; a server read from a source with neither, each meter's size instead | n/a | n/a |
| **Service** | one service: three observers, each with a mark per check, its latency and recent samples; state, age | plus how it is reached, where it runs, what it depends on, and where the edge in front answered from | n/a | n/a |
| **Time zones** | each zone's time, its places and marks | plus each zone's day ribbon, offset and name | each zone on a taller row, with its day | n/a |
| **Map** | the map, each place's mark, a short name where it fits | the map with its places named | plus each node named beside its place | the same, wider |

- **A mark per check.** In a narrow column (the small widget, and the medium widget's left), the bar's ticks wrap into a grid: every check as its mark, filled a column at a time in the bar's order, so trouble gathers at the right as it does on the bar. Up is quieter than trouble. Past what can be read, the stacked bar.
- **Room to spare** spreads between the blocks, up to twice their usual gap, instead of pooling above the foot.
- **The mark** sits small and a little muted in the corner: it says whose widget it is without competing with the verdict.
- **Fleet.** The extra large widget shows as many groups as fit. The rest are counted in a last cell that keeps their nodes' marks, trouble first, so trouble left out still shows.

Every widget is built from the same section models and the same renderer as the panel, in the same theme. In the cells renderer they become the TUI's boxes at 11 pt. In **Edit Widget**, users choose what a widget shows (the medium widget's right side; the server, including This Mac; the service; the map's framing, by default the panel's) and its theme (default: the same as the bar). They never choose what it means. Clicking a widget opens the panel; clicking an attention row opens the TUI on it.

### 7.2 Data

A widget extension runs in its own process and can't attach to the app's pipe. The app is the only reader of `topo`. After each frame it keeps the latest frame and the theme in its App Group container, and asks WidgetKit to reload:

- **At once** when the verdict state changes, or a widget-visible row changes health. With a Time zones widget on the desktop, that is every listed server; with a Map widget, every node and line on the map.
- **On a heartbeat** of 30 min while nothing changes.

Local readings are not offered in widgets, because a widget can't refresh often enough to show them live.

### 7.3 Honesty

Each reload gives WidgetKit two timeline entries:

- **Now:** the current verdict.
- **Not current:** dated at the next heartbeat plus 15 min.

If the app quits, crashes or the Mac sleeps through a renewal, the widget switches itself to **Not current**. It shows the last verdict as history ("Last known: 5 incidents · 47 min ago"), never as now. The widget's age line uses WidgetKit's relative date, which counts up without reloads.

A Time zones widget's timeline is longer: an entry each minute for an hour, twice the heartbeat, so a reload always comes first while the app runs. Its marks are current until the same moment as the others', then withheld (◌), and the clocks go on. Past the hour, the last entry draws places and offsets alone, its clocks "—".

### 7.4 Rendering modes

macOS draws desktop widgets without background or color while another app is in front. Shape-first glyphs keep every state readable there. In that mode, the cells renderer drops its box borders for plain headings, and the mark in a cards widget's corner is the globe's lines, as the menu bar item draws it at rest: flattened to one tone, the dithered globe on its paper would be a disc, and a disc is up's mark. A tick on the check bar has no shape of its own, so there weight tells them apart: trouble in the full ink, up faint.

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
  "style": { "box": "rules", "meter": "shade", "texture": "grain" },
  "tokens": {
    "ink": "#F5F0E6", "inkHigh": "#ECE5D7", "selection": "#E4DDCC", "key": "#E3DBCA", "line": "#BFB39C", "track": "#E2DACA",
    "text": "#2A2925", "muted": "#6E695D", "faint": "#A29C8E", "glow": "#FFFFFF", "accent": "#0F766E", "accent2": "#1D4ED8",
    "kind": "#BE185D", "up": "#15803D", "warning": "#B8720A", "down": "#B91C1C", "unknown": "#87929B",
    "grain": "rgba(80, 62, 30, .09)"
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
  - `cells` takes the slots above, and optionally `grain`, its texture's ink.
  - `cards` takes `accent`, `accent2`, `card`, `cardEdge`, `panelMaterial`, `panelMaterial2` (where a night surface deepens to), `fill`, `fill2`, `grain`, and optionally the status colors. Missing slots fall back to the system's. When it follows the system, `dark` and `light` may give any slot per appearance.
- **Style slots:** a theme's `style` names how its renderer draws beyond its colors. Each renderer declares its slots and the names each takes; one left out is the renderer's first.

  | Slot | `cards` | `cells` |
  |---|---|---|
  | `surface` | `glass`, `matte` (opaque, sections ruled), `night` (opaque, deepening, cards outlined) | n/a |
  | `box` | n/a | `rounded`, `rules` (a rule over each section), `corners` |
  | `meter` | `ticks`, `rule` (a scale), `dots` | `blocks`, `shade` (halftone), `braille` |
  | `titles` | `plain`, `caps` | n/a |
  | `texture` | `none`, `weave`, `grain` | `none`, `weave`, `grain` |

  ```json
  "style": { "surface": "matte", "meter": "rule", "titles": "caps", "texture": "weave" }
  ```
- **Type:** `font.family` is SF Pro, SF Pro Rounded or New York for `cards`, which draws SF Pro for any other. `cells` always draws SF Mono, which its grid is measured in. The size is the renderer's, scaled by the Text size setting.
- **Validation:** a theme is refused, with the reason, unless all of these hold:
  - text on ink is at least 4.5:1;
  - every pair of status colors differs by at least ΔE 15 (OKLab ×100) to normal vision, in each appearance it draws in. Under simulated color-blindness, pairs under ΔE 8 are reported as advisories: no green, orange and red palette keeps that margin, and every status has its own shape;
  - every required slot is present;
  - only a `cards` theme that follows the system gives `dark` and `light` sets;
  - every style slot is one its renderer has, set to a name it takes.
- **What a theme can't change:** glyphs, layout and meaning. A style changes how a surface is drawn; a mark is the same shape in every theme.
- **Where themes live:**
  - Built-in themes are compiled in.
  - User themes will be read from `~/Library/Application Support/topophany-bar/Themes/*.json`, then validated and copied into the App Group so widgets draw them too.
  - v1 ships the loader disabled, but every built-in theme goes through the same `Theme` type and validator, so the path is already exercised.
- **Swift types:** `Theme { id, renderer: RendererID, tokens: Tokens }`. `Renderer` is a protocol with `panel(_:)`, `statusItem(_:)` and `widget(_:family:)`, each taking section models and tokens.

**Aurora** and **Linen** (`cards`) and **Paper** and **Dusk** (`cells`) are built in, and each is only tokens and a style: proof that a theme file can look its own.

## 9. Configuration

**You choose what to look at, never what it means.**

| Yours (Settings, Edit Widget) | Fixed (topology + collector) |
|---|---|
| Theme; panel appearance; text size; panel height | What counts as up, warn, down or unknown |
| Menu bar: Symbol, Count or Words; status colors; motion; this Mac's readings; quiet its alert until it gets worse | Thresholds (`max_cpu_percent` and others, in `topology.json`) |
| Sections on or off and their order (Status is fixed) | Freshness, staleness, publisher lease |
| The time zone of each place | Each server's health in Time zones |
| Attention rows (3 or 5); which applications; pinned services and servers; the map's framing | How groups add up (unknown always counted) |
| What each widget shows and its theme | Status glyphs and their meaning |
| This Mac mode, readings, volume, interface, sample rate | No expressions or formulas |
| `topo`: found, chosen or downloaded; profile, observer view, refresh (1 s to 1 h); open at login; terminal for the TUI; language (system, English, Japanese, Simplified Chinese) | |

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
    { "id": "map", "enabled": true, "frame": "fit" },
    { "id": "applications", "only": [] },
    { "id": "services", "enabled": false, "ids": ["vless-entry", "main-site"] },
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

Dragging the panel's edge adds `"panelHeight": 640` to `appearance`, in points. Absent, the panel may be as tall as the screen allows.

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
                        Fleet, ServerCard, Zones, Map, Local; PlaceZones (a place's suggested time zone);
                        MapPlaces (where a place is, by its name);
                        Provider (who runs a node, by any of its names)
    TopophanyThemes/    Theme, Tokens, ThemeStore, ThemeValidator, Renderer protocol;
                        Cards/ (SwiftUI) and Cells/ (CellCanvas); Map/ (the map's layout, shared)
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
  1. **Finding `topo`:** the path setting, then the login shell's `PATH`, then `/opt/homebrew/bin` and `/usr/local/bin`, then the copies the app downloaded, newest first.
  2. **Version check:** run `topo monitor stream --capabilities`; if `topo` is too old to have it, or lacks protocol 1 or a metric, offer to download one (section 10.2.1).
  3. **When the engine stops:** restart it after 1, 2, 4 … up to 30 s, and show ◌ until the next frame.
  4. **When the app quits:** stdin closes and `topo` exits.

  Spawning a user-installed binary rules out the App Sandbox, so v1 is distributed with a Developer ID, notarized, on a disk image that the Homebrew cask also installs from. The image's window is the world laid flat in the icon's dither, ink on paper in its 2-point grain: the app and Applications on either side of the Pacific, joined by a route in ink, under one line of words (`scripts/make-dmg-background.swift`). It never scrolls, whatever bars Finder shows, and the names stay out of the way: Applications has none, and the app's sits on clear paper, where Finder's black in Light reads and its white in Dark vanishes.

#### 10.2.1 Getting topo

The app runs a `topo` that's already on the Mac, or one it downloads when the user asks. Nothing reaches the network until then.

- **Where it's offered:** while no `topo` can run, as Download topo in the Status card and in Settings; and at any time in the menu of Settings' topo row: Download Latest, or the release this app was tested with.
- **The latest:** GitHub's API names topophany's latest release and its archive for this Mac (`darwin_arm64` on Apple silicon, even under Rosetta, else `darwin_amd64`). The archive's SHA-256 comes from the API's `digest`, or else the release's `SHA256SUMS.txt`; without one it isn't downloaded.
- **The tested release:** fixed in the app with its archives' SHA-256 (`TopoRelease.tested`), so it never depends on what the API says. It's the fallback when the latest doesn't work: when a downloaded latest lacks protocol 1, the offer becomes this release.
- **Before it's kept:** the archive must match its hash, hold a regular file `topo`, and pass the version check. Then its folder, with topo's own license, goes to `topo/<version>/` beside the settings file, replacing a copy of the same version, and the path setting names it.
- **Choosing:** Settings' topo row lists every `topo` on the Mac, once each however it's linked, with its version; one without `monitor stream` is shown and can't be chosen. Choose… picks any other file.
- **Deleting:** any downloaded copy, even the one running or the only one. The app then searches again, and offers to download when it finds none.
- **Signing in:** a `topo` with no saved profile can sign in from Settings. The app asks for the server, project and profile name, and runs `topo login` with them in the user's terminal, which asks for the token itself. The app never sees it.
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
| `service.card` | `card`, `select.service` | from `Fleet().ServiceCard`: `seen_from` by observer, each check with its own deadline, latency, share up and recent samples; endpoints, colos, dependencies |
| `services.list` | `list` | per service: `id`, `name`, application, `health`, host; for choosing |
| `map.graph` | `map` | from `View.Graph()`: nodes with their place, coordinates and signal; links, path hops and colos with theirs |

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
5. **Polish:** VoiceOver, Reduce Transparency and Increase Contrast, keyboard navigation, localization (en, ja, zh), signing, notarization, the disk image and the cask.

Later: user theme files, EmbeddedEngine and `libtopo`, more renderers.

## 13. Open questions

- Should Seen from collapse to counts beyond about 20 observers?
- Should the Terminal theme follow the user's terminal font when one is set?
- What should the widget heartbeat be: 30 min, or tuned to the observed reload budget?

## 13. Beszel and Komari direct (D1)

Direct extends the existing client/preview product with a third, exclusive reading
mode. Data still flows Engine → Kit → Sections → Themes. Platform-independent
packages remain AppKit-free. There is no new dashboard or WebView.

Settings adds a Data sources toolbar tab using the existing `SettingsForm`, native
pickers, secure fields, grouped rows and delete confirmation. One row says where
readings come from; one Sources group holds the profile, a row per source (its Hub
or server, its servers and, while the bar reads it, its state; its kind too where
the profile mixes Beszel and Komari) and Add Source…. A source's button is what it
needs, Sign In… when its sign-in lapsed and Edit… otherwise; the rest are in its
menu. The editor sheet sizes to what it shows and follows source → test → server
selection (checkboxes, "2 of 20 chosen") → save; Settings grows to hold it. A new
source chooses its kind first, Beszel or Komari, from the adapters `topo` offers;
an existing one keeps its own. The kind sets the words and the sign-in: a Hub URL
with account and password or an API token for Beszel; a server URL with an API key,
or public servers only, for Komari, read every 30 seconds unless the interval was
changed. Switching kinds drops what was typed for the other. Source ID and system
ID carry identity; names are presentation only. Advanced fields expose the Go
ranges without a TLS bypass. Passwords, tokens and API keys never become Settings
or App Group properties.

The status card receives `SourceStatusSection`, which describes acquisition rather
than a collector verdict. Its headline is the state alone: Connected, Needs
attention, Connecting, No resource samples, Source unavailable. Under it, Go's
counts as the collector card words its checks, "3 of 3 servers current", naming
stale and missing servers only when there are some. Connected draws a signal in its
tile, never All clear's check. Each source follows with its mark and what its row
ends in: its servers while connected ("2 of 2 current"), else the state that asks
for a look, in weight. A row opens Data sources. The foot counts sources and says
when the frame came. Count uses Go's attention count. No incident count or All
clear is synthesized. The same card/row typography and theme tokens apply to Cards
and Cells, where the servers current are the big number. The header names the
adapter as a collector's names its view. A server card says where it's read from
in the provider's place ("host · Home Beszel"); Fleet adds no badge, and counts no
providers when none are known. Provider logos retain their established meaning.

Go judges no health for a direct server, so its card, never UNKNOWN for that,
says how it is read, from the selected resource's own freshness and health:
CURRENT in the resource's mark (● while Go calls the reading up), STALE once a
sample has expired, NO SAMPLES before one is usable; both ◌, and a stale card's
age reads "last reading …". The same marks lead Fleet's servers, the widgets'
rows and a Terminal card's title; a listed server whose card isn't read stays ○.
With nothing else to say, a Native card adds each meter's size beneath it ("8
CPUs", "8.4 / 16 GiB"), as the Terminal card's detail column does. Both sizes take
the total's binary unit, MiB to PiB: "1.2 / 3.6 TiB". A server whose
health Go does judge keeps UP, WARN or DOWN.

The rule follows the source, not the mode: Komari and Beszel servers reach the bar
directly or through a collector's topology, carrying `origin.adapter` "komari" or
"beszel". Their cards name it in the provider's place ("host · Komari Monitor"),
and an unjudged one reads as above. A Komari disk is the aggregate its agent
reports, not one mount; the editor's server list says so. In collector mode, Data
sources lists, read-only, the sources the collector's server list names (Komari,
Beszel), each with its servers; they are set up in the topology. Source rows in direct mode lead with a dot, as General's
engine row does: green while connected, orange when it asks for a look, a ring
while it isn't read.
Unsupported collector sections are hidden in direct mode without changing their
saved preferences. Settings → Sections lists them faint, "Needs a collector" in
place of their switches, and Status says what it shows there: each source's state.

Direct widgets use the existing sizes and themes, show an As of time, and become
history at the original relevant deadlines. A Status widget is the state and its
sources in a narrow column, over a bar of the selected servers as the collector's
bar draws checks: a tick each, current calm, stale and without samples outlined,
hatched once not current. The subtitle wraps only between its parts, in Japanese
and Chinese too. The medium, large and extra large add the pinned servers'
readings, a row each with CPU, memory and disk (a short meter beside each where
there is room), "—" where withheld, as many as fit and the rest counted; a server
with no current sample says STALE or NO SAMPLES across its columns instead.
While every pinned server fits in one, the large and extra large give each a tile
instead: its mark and name, its source where servers come from more than one (or
its STALE or NO SAMPLES while the name still fits whole), and its three meters,
with their sizes where the tile is wide. Past what rows of meters hold, dense
tiles set the three side by side, each value over its meter, labelled once over
each column of tiles. The extra large then spans the widget, the state beside its
sources above the tiles. The cells renderer draws the tiles as boxes. In the large
widget the sources rows outrank the tiles. With none pinned, the widget lists the
sources instead, each over its own servers' bar, and the large and extra large say
where to pin servers. A medium Server widget for a server read from a source,
which has no services to list, sets its three readings across the widget, each
large over its meter and its size, its pill and As of time at the top. A new
handoff cannot renew measurements. Their node choices carry dataset identity so
a Hub/account/profile change cannot silently reuse a choice. Static ImageRenderer
coverage includes all six themes, three languages, acquisition states, several
sources and servers, and the Widget sizes at both the design's and a 1080 pt
display's bounds. Evidence and system validation limits are recorded in
`docs/contracts/direct-v1/HANDOFF.md`.
