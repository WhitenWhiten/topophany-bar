#!/usr/bin/env python3
"""Draws Topophany's globe: the app icon and the mark, from one dither.

The globe is the Earth seen from 20°N 140°E, lit from the upper left, in the
homepage's ink on paper and its 8×8 ordered (Bayer) dither. By day the sea is
a checkerboard, the land is paper, and night falls across the terminator into
solid ink; the limb is drawn in ink. By night the same globe is light on ink:
the dots are its light, and the limb is the atmosphere, a ring of them.

- Apps/topophany-bar/AppIcon.icon: 64 cells across the 1024-point canvas, so
  a cell is a whole number of pixels at 64 pixels and up. globe.svg is the
  ink on the paper fill, globe-dark.svg the light on the ink, for the dark,
  tinted and clear appearances. The layer is matte, without glass.
- design/assets/mark.svg: 16 cells, ink on a paper disc, and light alone where
  the viewer prefers dark. Topophany's favicon.
- Sources/TopophanyThemes/BrandMarkData.swift: the mark's cells, for BrandMark.

The land is design/assets/land.bin: Natural Earth 1:110m land (public
domain) in 0.5° cells, row 0 at 90°N, column 0 at 180°W, as topo draws it.

    python3 -I scripts/make-icon.py

To see an appearance as the system draws it, use the ictool inside Icon
Composer (Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables):

    ictool Apps/topophany-bar/AppIcon.icon --export-image --output-file icon.png \\
      --platform macOS --rendition Default --width 1024 --height 1024 --scale 1

Renditions are Default, Dark, TintedLight, TintedDark, ClearLight and ClearDark.
"""
import json
import math
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
LAND = open(os.path.join(ROOT, "design", "assets", "land.bin"), "rb").read()
assert len(LAND) == 720 * 360 // 8, "land.bin should be 720 × 360 bits"

FACING = (20.0, 140.0)                     # what the globe faces, latitude and longitude
INK, PAPER, GLOW = "#1a1a1a", "#ffffff", "#f4f2ec"
BAYER = [0, 32, 8, 40, 2, 34, 10, 42, 48, 16, 56, 24, 50, 18, 58, 26,
         12, 44, 4, 36, 14, 46, 6, 38, 60, 28, 52, 20, 62, 30, 54, 22,
         3, 35, 11, 43, 1, 33, 9, 41, 51, 19, 59, 27, 49, 17, 57, 25,
         15, 47, 7, 39, 13, 45, 5, 37, 63, 31, 55, 23, 61, 29, 53, 21]


def unit(v):
    n = math.sqrt(sum(a * a for a in v))
    return tuple(a / n for a in v)


def smoothstep(e0, e1, x):
    t = min(1.0, max(0.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


LIGHT = unit((-0.55, 0.6, 0.58))           # from the left, above, and toward us
LAT0, LON0 = math.radians(FACING[0]), math.radians(FACING[1])


def is_land(lat, lon):
    l = (lon + 180) % 360
    i = min(359, max(0, int((90 - lat) * 2))) * 720 + min(719, int(l * 2))
    return LAND[i >> 3] & (0x80 >> (i & 7)) != 0


def geographic(x, y):
    """A point on the unit disc (y up) to latitude and longitude, or None off it."""
    r2 = x * x + y * y
    if r2 >= 1:
        return None
    z = math.sqrt(1 - r2)
    lat = math.asin(max(-1.0, min(1.0, z * math.sin(LAT0) + y * math.cos(LAT0))))
    lon = LON0 + math.atan2(x, z * math.cos(LAT0) - y * math.sin(LAT0))
    return math.degrees(lat), math.degrees(lon)


def globe(cells, radius, limb):
    """Each cell of a cells × cells grid holding a globe `radius` cells across
    its middle: (inside, ink by day, light by night). `limb` is where the
    limb's ink begins and ends, as 1 - z."""
    rows = []
    for j in range(cells):
        row = []
        for i in range(cells):
            x, y = (i + 0.5 - cells / 2) / radius, (cells / 2 - j - 0.5) / radius
            r = math.hypot(x, y)
            if r >= 1:
                row.append((False, False, False))
                continue
            z = math.sqrt(1 - r * r)
            # Land where most of the cell is.
            hits = sum(1 for v in range(4) for u in range(4)
                       if (g := geographic(x + (u - 1.5) / 4 / radius, y + (v - 1.5) / 4 / radius)) and is_land(*g))
            land = hits >= 8
            # By day the sea is a checkerboard and the land paper, each a
            # little darker away from the light; night falls across the
            # terminator into solid ink.
            nl = x * LIGHT[0] + y * LIGHT[1] + z * LIGHT[2]
            shade = 1 - max(0.0, nl)
            surface = 0.15 * shade if land else 0.5 + 0.1 * shade
            day = smoothstep(-0.12, 0.45, nl)
            surface = surface * day + (1 - day)
            # Ink draws the limb by day; by night it is a ring of light.
            rim = smoothstep(limb[0], limb[1], 1 - z)
            ink = max(surface, rim)
            glow = max(1 - ink, 0.6 * rim)
            t = (BAYER[(j & 7) * 8 + (i & 7)] + 0.5) / 64
            row.append((True, ink > t, glow > t))
        rows.append(row)
    return rows


def path(rows, k, cell):
    """The cells where the k-th of each is set, as one path of runs, so they
    fill without seams."""
    d = []
    for j, row in enumerate(rows):
        i = 0
        while i < len(row):
            if not row[i][k]:
                i += 1
                continue
            start = i
            while i < len(row) and row[i][k]:
                i += 1
            d.append(f"M{start * cell:g} {j * cell:g}h{(i - start) * cell:g}v{cell:g}h-{(i - start) * cell:g}z")
    return "".join(d)


def srgb(colour):
    return "srgb:" + ",".join(f"{int(colour[i:i + 2], 16) / 255:.5f}" for i in (1, 3, 5)) + ",1.00000"


def write(relative, text):
    out = os.path.join(ROOT, relative)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    open(out, "w", encoding="utf-8").write(text)
    print(relative)


# MARK: the app icon

icon = globe(64, 22, (0.45, 0.85))
for name, k, colour in (("globe.svg", 1, INK), ("globe-dark.svg", 2, GLOW)):
    write(f"Apps/topophany-bar/AppIcon.icon/Assets/{name}",
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">'
          f'<path fill="{colour}" d="{path(icon, k, 16)}"/></svg>\n')
write("Apps/topophany-bar/AppIcon.icon/icon.json", json.dumps({
    "fill-specializations": [
        {"value": {"solid": srgb(PAPER)}},
        {"appearance": "dark", "value": {"solid": srgb(INK)}},
    ],
    "groups": [{
        "layers": [{
            "glass": False,
            "image-name-specializations": [
                {"value": "globe.svg"},
                {"appearance": "dark", "value": "globe-dark.svg"},
                {"appearance": "tinted", "value": "globe-dark.svg"},
            ],
            "name": "globe",
        }],
        "shadow": {"kind": "none", "opacity": 0},
        "specular": False,
        "translucency": {"enabled": False, "value": 0},
    }],
    "supported-platforms": {"squares": ["macOS"]},
}, indent=2) + "\n")

# MARK: the mark

mark = globe(16, 8, (0.3, 0.6))
write("design/assets/mark.svg",
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" shape-rendering="crispEdges">'
      "<style>.night{display:none}@media(prefers-color-scheme:dark){.day{display:none}.night{display:inline}}</style>"
      f'<g class="day"><path fill="{PAPER}" d="{path(mark, 0, 1)}"/><path fill="{INK}" d="{path(mark, 1, 1)}"/></g>'
      f'<path class="night" fill="{GLOW}" d="{path(mark, 2, 1)}"/></svg>\n')


def bits(k):
    return [f"        0b{''.join('1' if c[k] else '0' for c in row)}," for row in mark]


write("Sources/TopophanyThemes/BrandMarkData.swift", "\n".join([
    "// Generated by scripts/make-icon.py. Don't edit.",
    "",
    "extension BrandMark {",
    "    /// The globe's disc, a row of 16 cells to a number, the leftmost the highest bit.",
    "    static let disc: [UInt16] = [",
    *bits(0),
    "    ]",
    "",
    "    /// Its ink by day.",
    "    static let day: [UInt16] = [",
    *bits(1),
    "    ]",
    "",
    "    /// Its light by night.",
    "    static let night: [UInt16] = [",
    *bits(2),
    "    ]",
    "}",
    "",
]))
