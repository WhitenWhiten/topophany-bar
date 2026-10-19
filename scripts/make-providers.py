#!/usr/bin/env python3
"""Writes the providers topophany-bar knows, from design/assets/providers.js.

Sources/TopophanySections/ProviderTable.swift gets each provider's name,
the names a topology may give it, its color and its mark.
Sources/TopophanyThemes/ProviderLogoData.swift gets each logo as one
outline in a box as wide and tall as the logo, its longer side 1, in
absolute M, L, Q, C and Z only: arcs become curves, relative and smooth
commands absolute, and topo's outlines, y up, are turned y down. Swift then
reads each outline in one pass. design/assets/provider-logos.js gets the
same outlines for the previews, so both draw the same shapes.

    python3 -I scripts/make-providers.py
"""
import json
import math
import os
import re

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SOURCE = os.path.join(ROOT, "design", "assets", "providers.js")
TABLE = os.path.join(ROOT, "Sources", "TopophanySections", "ProviderTable.swift")
LOGOS = os.path.join(ROOT, "Sources", "TopophanyThemes", "ProviderLogoData.swift")
PREVIEW = os.path.join(ROOT, "design", "assets", "provider-logos.js")
OPTICAL = 0.92

NUMBER = re.compile(r"[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?")
ARITY = {"M": 2, "L": 2, "H": 1, "V": 1, "C": 6, "S": 4, "Q": 4, "T": 2, "A": 7, "Z": 0}


def read_source():
    js = open(SOURCE, encoding="utf-8").read()
    start = js.index("window.TB_PROVIDERS = {") + len("window.TB_PROVIDERS = ")
    end = js.index("\n};", start) + 2
    body = js[start:end]
    # The file is JSON but for the trailing comma after the last entry.
    return json.loads(re.sub(r",\n}$", "\n}", body))


def normalized(name):
    """A name with case and everything but letters and digits removed, as
    Provider.normalized does it."""
    return "".join(c for c in name.lower() if c.isalnum())


def tokens(d):
    """The path's commands and their numbers. An arc's two flags are single
    digits that may run together and into the next number."""
    i, n = 0, len(d)
    out = []
    while i < n:
        c = d[i]
        if c.isspace() or c == ",":
            i += 1
            continue
        assert c.upper() in ARITY, f"unknown command {c!r} at {i}"
        i += 1
        args = []
        arity = ARITY[c.upper()]
        while arity:
            group = []
            for k in range(arity):
                while i < n and (d[i].isspace() or d[i] == ","):
                    i += 1
                if c.upper() == "A" and k in (3, 4):
                    assert d[i] in "01", f"arc flag {d[i]!r} at {i}"
                    group.append(float(d[i]))
                    i += 1
                    continue
                m = NUMBER.match(d, i)
                if not m:
                    break
                group.append(float(m.group()))
                i = m.end()
            if not group:
                break
            assert len(group) == arity, f"{c} wants {arity} numbers, got {group}"
            args.append(group)
            while i < n and (d[i].isspace() or d[i] == ","):
                i += 1
            if i >= n or d[i].isalpha():
                break
        out.append((c, args if arity else [[]]))
    return out


def arc(x0, y0, rx, ry, phi, large, sweep, x, y):
    """An elliptical arc as cubic curves, SVG's endpoint parameterization
    turned into centre and angles (SVG 1.1, appendix F.6)."""
    if (x0, y0) == (x, y):
        return []
    rx, ry = abs(rx), abs(ry)
    if rx == 0 or ry == 0:
        return [("L", x, y)]
    cos, sin = math.cos(math.radians(phi)), math.sin(math.radians(phi))
    dx, dy = (x0 - x) / 2, (y0 - y) / 2
    x1 = cos * dx + sin * dy
    y1 = -sin * dx + cos * dy
    scale = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
    if scale > 1:
        rx, ry = rx * math.sqrt(scale), ry * math.sqrt(scale)
    num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
    den = rx * rx * y1 * y1 + ry * ry * x1 * x1
    k = math.sqrt(max(0, num / den)) * (-1 if large == sweep else 1)
    cx1, cy1 = k * rx * y1 / ry, -k * ry * x1 / rx
    cx = cos * cx1 - sin * cy1 + (x0 + x) / 2
    cy = sin * cx1 + cos * cy1 + (y0 + y) / 2

    def angle(ux, uy, vx, vy):
        a = math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        return a

    t1 = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
    dt = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
    if not sweep and dt > 0:
        dt -= 2 * math.pi
    elif sweep and dt < 0:
        dt += 2 * math.pi
    parts = max(1, math.ceil(abs(dt) / (math.pi / 2) - 1e-9))
    step = dt / parts
    alpha = 4 / 3 * math.tan(step / 4)

    def point(t):
        ex, ey = rx * math.cos(t), ry * math.sin(t)
        return cos * ex - sin * ey + cx, sin * ex + cos * ey + cy

    def tangent(t):
        ex, ey = -rx * math.sin(t), ry * math.cos(t)
        return cos * ex - sin * ey, sin * ex + cos * ey

    out = []
    t = t1
    for p in range(parts):
        a, b = t, t + step
        pa, pb = point(a), point(b)
        ta, tb = tangent(a), tangent(b)
        end = (x, y) if p == parts - 1 else pb
        out.append(("C", pa[0] + alpha * ta[0], pa[1] + alpha * ta[1], pb[0] - alpha * tb[0], pb[1] - alpha * tb[1],
                    end[0], end[1]))
        t = b
    return out


def absolute(d):
    """The path as absolute M, L, Q, C and Z segments."""
    segs = []
    x = y = sx = sy = 0.0
    last_c = last_q = None
    for cmd, groups in tokens(d):
        up = cmd.upper()
        rel = cmd != up
        for gi, g in enumerate(groups):
            ox, oy = (x, y) if rel else (0.0, 0.0)
            prev_c, prev_q = last_c, last_q
            last_c = last_q = None
            if up == "M":
                x, y = g[0] + ox, g[1] + oy
                if gi == 0:
                    segs.append(("M", x, y))
                    sx, sy = x, y
                else:
                    segs.append(("L", x, y))
            elif up == "L":
                x, y = g[0] + ox, g[1] + oy
                segs.append(("L", x, y))
            elif up == "H":
                x = g[0] + (x if rel else 0)
                segs.append(("L", x, y))
            elif up == "V":
                y = g[0] + (y if rel else 0)
                segs.append(("L", x, y))
            elif up == "C":
                c1 = (g[0] + ox, g[1] + oy)
                c2 = (g[2] + ox, g[3] + oy)
                x, y = g[4] + ox, g[5] + oy
                segs.append(("C", *c1, *c2, x, y))
                last_c = c2
            elif up == "S":
                c1 = (2 * x - prev_c[0], 2 * y - prev_c[1]) if prev_c else (x, y)
                c2 = (g[0] + ox, g[1] + oy)
                x, y = g[2] + ox, g[3] + oy
                segs.append(("C", *c1, *c2, x, y))
                last_c = c2
            elif up == "Q":
                c = (g[0] + ox, g[1] + oy)
                x, y = g[2] + ox, g[3] + oy
                segs.append(("Q", *c, x, y))
                last_q = c
            elif up == "T":
                c = (2 * x - prev_q[0], 2 * y - prev_q[1]) if prev_q else (x, y)
                x, y = g[0] + ox, g[1] + oy
                segs.append(("Q", *c, x, y))
                last_q = c
            elif up == "A":
                ex, ey = g[5] + ox, g[6] + oy
                segs += arc(x, y, g[0], g[1], g[2], int(g[3]), int(g[4]), ex, ey)
                x, y = ex, ey
            elif up == "Z":
                segs.append(("Z",))
                x, y = sx, sy
    return segs


def flip(segs):
    return [(s[0], *[v if i % 2 == 0 else -v for i, v in enumerate(s[1:])]) for s in segs]


def bounds(segs):
    """The outline's extent, its curves sampled finely enough for a logo."""
    xs, ys = [], []
    px = py = 0.0
    for s in segs:
        kind = s[0]
        if kind in ("M", "L"):
            px, py = s[1], s[2]
            xs.append(px)
            ys.append(py)
        elif kind == "Q":
            for k in range(1, 33):
                t = k / 32
                xs.append((1 - t) ** 2 * px + 2 * (1 - t) * t * s[1] + t * t * s[3])
                ys.append((1 - t) ** 2 * py + 2 * (1 - t) * t * s[2] + t * t * s[4])
            px, py = s[3], s[4]
        elif kind == "C":
            for k in range(1, 33):
                t = k / 32
                a, b, c, e = (1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t * t, t ** 3
                xs.append(a * px + b * s[1] + c * s[3] + e * s[5])
                ys.append(a * py + b * s[2] + c * s[4] + e * s[6])
            px, py = s[5], s[6]
    return min(xs), min(ys), max(xs), max(ys)


def fmt(v):
    s = f"{v:.4f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def outline(logo):
    segs = absolute(logo["d"])
    if logo["up"]:
        segs = flip(segs)
    x0, y0, x1, y1 = bounds(segs)
    k = 1 / max(x1 - x0, y1 - y0)
    out = []
    for s in segs:
        vals = [(v - x0) * k if i % 2 == 0 else (v - y0) * k for i, v in enumerate(s[1:])]
        out.append(s[0] + " ".join(fmt(v) for v in vals))
    return (x1 - x0) * k, (y1 - y0) * k, "".join(out)


def swift_string(s):
    return json.dumps(s, ensure_ascii=False)


def main():
    providers = read_source()
    seen = {}
    for key, p in providers.items():
        assert re.fullmatch(r"[a-z0-9]+", key), key
        for n in p["names"]:
            assert n == normalized(n), f"{key}: {n!r} isn't normalized"
            assert n not in seen, f"{n!r} names both {seen.get(n)} and {key}"
            seen[n] = key
        assert normalized(p["name"]) in p["names"] or normalized(p["name"]) not in seen, key
        assert p["color"] == "" or re.fullmatch(r"#[0-9A-F]{6}", p["color"]), (key, p["color"])

    head = "// Generated by scripts/make-providers.py from design/assets/providers.js. Don't edit.\n\n"
    rows = []
    for key, p in providers.items():
        names = set(p["names"]) | {normalized(p["name"])}
        names = [n for n in p["names"]] + sorted(names - set(p["names"]))
        color = "0x" + p["color"][1:] if p["color"] else "nil"
        rows.append(f"        Provider(key: {swift_string(key)}, name: {swift_string(p['name'])}, "
                    f"names: [{', '.join(swift_string(n) for n in names)}], color: {color}, "
                    f"mark: {swift_string(p['mark'])}, hasLogo: {'true' if 'logo' in p else 'false'}),")
    with open(TABLE, "w", encoding="utf-8") as f:
        f.write(head + "extension Provider {\n"
                "    /// Every provider topophany-bar knows: the ones topo knows, in its\n"
                "    /// spelling and colors, then more.\n"
                "    static let table: [Provider] = [\n" + "\n".join(rows) + "\n    ]\n}\n")

    rows, js = [], []
    for key, p in providers.items():
        if "logo" not in p:
            continue
        w, h, d = outline(p["logo"])
        k = p.get("optical", OPTICAL)
        assert 0.5 < k < 1.2, (key, k)
        rows.append(f"        {swift_string(key)}: ({fmt(w)}, {fmt(h)}, {fmt(k)}, {swift_string(d)}),")
        js.append(f"  {swift_string(key)}: [{fmt(w)}, {fmt(h)}, {fmt(k)}, {swift_string(d)}],")
    with open(LOGOS, "w", encoding="utf-8") as f:
        f.write(head + "extension ProviderLogo {\n"
                "    /// Each logo's width and height, its longer side 1; how large it is\n"
                "    /// drawn against the box it fits; and its outline.\n"
                "    static let outlines: [String: (Double, Double, Double, String)] = [\n" + "\n".join(rows) + "\n    ]\n}\n")
    with open(PREVIEW, "w", encoding="utf-8") as f:
        f.write("// Generated by scripts/make-providers.py from providers.js. Don't edit.\n"
                "// Each logo's width and height, its longer side 1; how large it is drawn\n"
                "// against the box it fits; and its outline.\n"
                "window.TB_LOGOS = {\n" + "\n".join(js) + "\n};\n")
    print(f"{len(providers)} providers, {len(rows)} logos")


if __name__ == "__main__":
    main()
