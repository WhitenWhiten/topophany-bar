#!/usr/bin/env python3
"""Writes the NDJSON fixtures the FixtureEngine replays.

Every line is a frame of `topo monitor stream` as docs/PROTOCOL.md defines
it, for the preview network of design/assets/data.js (`topo preview`'s
homelab). Times are anchored at ANCHOR: the FixtureEngine shifts them so
that ANCHOR is the moment replay starts. Frames at or before it are sent at
once; later ones when the clock reaches them.

    python3 -I scripts/make-fixtures.py
"""

import copy
import json
import os
from datetime import datetime, timedelta, timezone

ANCHOR = datetime(2026, 10, 18, 13, 30, 0, tzinfo=timezone.utc)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Sources", "TopophanyEngine", "Fixtures")
GIB = 1 << 30
GB = 1000 ** 3


def ts(t):
    return t.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def at(seconds):
    return ANCHOR + timedelta(seconds=seconds)


# ------------------------------------------------------------------ network

# Observers: id, name, node, checks they run.
OBSERVERS = [
    ("seattle-macbook", "Seattle MacBook", "macbook", 14),
    ("seattle-windows", "Seattle Windows", "seattle-pc", 8),
    ("home-router", "Home Router", "router", 3),
    ("san-jose", "San Jose", "sj-vultr", 6),
    ("ny-oracle", "New York Oracle", "oracle-ny", 9),
    ("ny-azure", "New York Azure", "azure-ny", 5),
    ("la-bwh", "LA BandwagonHost", "bwh-la", 6),
    ("la-oracle", "LA Oracle", "oracle-la", 3),
    ("frankfurt", "Frankfurt", "fra-hetzner", 4),
    ("tokyo", "Tokyo", "tokyo-vps", 3),
    ("honolulu", "Honolulu", "hnl-vultr", 7),
]
assert sum(o[3] for o in OBSERVERS) == 68

APPS = [
    ("proxy", "Proxy chain", [
        ("vless-entry", "VLESS+Reality Entry (Primary)"), ("exit-a", "Exit Candidate A"), ("exit-b", "Exit Candidate B"),
        ("relay", "Relay contrast"), ("oracle-exit-a", "Oracle Exit A"), ("vultr-exit-b", "Vultr Exit B")]),
    ("code", "Code & backups", [("gitea", "Gitea"), ("restic", "Restic Backups"), ("nightly-backup", "Nightly Backup")]),
    ("site", "Main site", [("main-site", "Main Site (Caddy + Blog)"), ("main-api", "Main Site API"), ("memos", "Memos")]),
    ("cloud", "Personal cloud", [("nextcloud", "Nextcloud"), ("immich", "Immich"), ("vaultwarden", "Vaultwarden"),
                                 ("syncthing", "Syncthing"), ("jellyfin", "Jellyfin")]),
    ("remote", "Remote access", [("tailscale", "Tailscale"), ("ssh-bastion", "SSH Bastion")]),
    ("serverless", "Serverless", [("workers-api", "Workers API"), ("pages", "Pages"), ("r2-gateway", "R2 Gateway"),
                                  ("queue", "Queue Consumer")]),
]
UNMONITORED = {"nightly-backup"}

SERVERS = {
    "oracle-ny": dict(name="Oracle New York", kind="host", provider="Oracle", where="New York", check="oracle-ny-host",
                      observer="ny-oracle", cpu=(26.3, 90, 8), mem=(46.2, 90, int(7.4 * GIB), 16 * GIB),
                      disk=(58.4, 90, 150 * GIB, 256 * GIB), process=("caddy", 1),
                      services=["main-site", "main-api", "memos", "nightly-backup"]),
    "bwh-la": dict(name="BandwagonHost LA", kind="host", provider="BandwagonHost", where="Los Angeles", check="bwh-la-host",
                   observer="la-bwh", cpu=(41.0, 90, 4), mem=(63.5, 85, int(2.54 * GIB), 4 * GIB),
                   disk=(84.2, 90, int(33.7 * GIB), 40 * GIB), process=None,
                   services=["vless-entry", "exit-a", "exit-b", "relay", "oracle-exit-a", "vultr-exit-b"]),
    "macbook": dict(name="MacBook Pro", kind="laptop", provider="Home", where="Seattle", check="macbook-host",
                    observer="seattle-macbook", cpu=(18.2, 95, 14), mem=(68.0, 95, int(16.3 * GIB), 24 * GIB),
                    disk=(43.7, 90, 107 * GB, 245 * GB), process=None, services=["tailscale", "topo-worker"]),
}
SERVICE_NAMES = {sid: name for _, _, svcs in APPS for sid, name in svcs}
SERVICE_NAMES["topo-worker"] = "Topophany worker"

# --------------------------------------------------------------- scenarios

# Per scenario: observer overrides (counts and liveness), service healths,
# attention entries, server overrides and the verdict.
SCENARIOS = {
    "clear": dict(
        verdict=("clear", "●", "ALL CLEAR", dict(up=68, warning=0, down=0, unknown=0), 0),
        observers={}, services={}, attention=[], attention_total=0, servers={}),
    "degraded": dict(
        verdict=("degraded", "▲", "DEGRADED", dict(up=66, warning=2, down=0, unknown=0), 0),
        observers={"seattle-macbook": dict(warning=1), "seattle-windows": dict(warning=1)},
        services={"vless-entry": "degraded", "exit-a": "degraded"},
        attention=[
            dict(kind="service", id="vless-entry", title="Seattle MacBook → VLESS+Reality Entry (Primary)",
                 observer="seattle-macbook", health="degraded", state="warn"),
            dict(kind="path", id="exit-candidates", title="Seattle Windows → Exit Candidates (BandwagonHost · Azure)",
                 observer="seattle-windows", health="degraded", state="warn"),
        ],
        attention_total=2, servers={}),
    "incidents": dict(
        verdict=("incidents", "✖", "5 INCIDENTS", dict(up=63, warning=0, down=5, unknown=0), 5),
        observers={"seattle-windows": dict(down=3), "seattle-macbook": dict(down=1), "san-jose": dict(down=1)},
        services={"vless-entry": "degraded", "exit-a": "degraded", "relay": "degraded"},
        attention=[
            dict(kind="incident", id="inc-7f3a", title="Seattle MacBook → Primary BandwagonHost → Oracle Exit A",
                 observer="seattle-macbook", since=-240, health="down", state="open"),
            dict(kind="incident", id="inc-7f3b", title="San Jose → Relay contrast → BandwagonHost LA",
                 observer="san-jose", since=-238, health="down", state="open"),
            dict(kind="incident", id="inc-7f3c", title="Seattle Windows → Direct entry to BandwagonHost",
                 observer="seattle-windows", since=-236, health="down", state="open"),
            dict(kind="incident", id="inc-7f3d", title="Seattle Windows → Primary BandwagonHost → Oracle Exit A",
                 observer="seattle-windows", since=-190, health="down", state="open"),
            dict(kind="incident", id="inc-7f3e", title="Seattle Windows → Primary BandwagonHost → Vultr Exit B",
                 observer="seattle-windows", since=-185, health="down", state="open"),
        ],
        attention_total=17,
        servers={"bwh-la": dict(health="degraded", note="affected",
                                services={"vless-entry": "degraded", "exit-a": "degraded", "relay": "degraded"},
                                affected={"vless-entry", "exit-a", "relay"})}),
    "incomplete": dict(
        verdict=("incomplete", "○", "INCOMPLETE EVIDENCE", dict(up=61, warning=0, down=0, unknown=7), 0),
        observers={"honolulu": dict(unknown=7, live=False, last_seen=-180)},
        services={"oracle-exit-a": "unknown", "vultr-exit-b": "unknown"},
        attention=[
            dict(kind="observer", id="honolulu", title="Honolulu Vultr", observer="honolulu", health="unknown",
                 state="unknown"),
            dict(kind="path", id="transit-internet", title="Honolulu → Transit → Internet", observer="honolulu",
                 health="unknown", state="unknown"),
        ],
        attention_total=2, servers={}),
}

# ----------------------------------------------------------------- frames

ROWS = [
    dict(id="status", label="", metric="summary.verdict", visual="status", select={}),
    dict(id="seen", label="", metric="observers.verdicts", visual="list", select={}),
    dict(id="attention", label="", metric="attention.list", visual="list", select={}, limit=5),
    dict(id="apps", label="", metric="applications.list", visual="list", select={}),
    dict(id="server-1", label="", metric="server.card", visual="card", select={"node": "oracle-ny"}),
    dict(id="server-2", label="", metric="server.card", visual="card", select={"node": "bwh-la"}),
    dict(id="mac", label="", metric="server.card", visual="card", select={"node": "macbook"}),
]

SEVERITY = {"down": 0, "degraded": 1, "unknown": 2, "up": 3}
WORD = {"clear": "up", "degraded": "degraded", "incidents": "down", "down": "down"}


def worst(healths):
    hs = list(healths)
    return min(hs, key=lambda h: SEVERITY[h]) if hs else "up"


def observer_entries(sc, t):
    out = []
    for oid, name, node, checks in OBSERVERS:
        o = sc["observers"].get(oid, {})
        down, warning, unknown = o.get("down", 0), o.get("warning", 0), o.get("unknown", 0)
        live = o.get("live", True)
        if not live:
            state, health = "incomplete", "unknown"
        elif down:
            state, health = "incidents" if sc["verdict"][4] else "down", "down"
        elif warning:
            state, health = "degraded", "degraded"
        elif unknown:
            state, health = "incomplete", "unknown"
        else:
            state, health = "clear", "up"
        out.append(dict(id=oid, name=name, node=node, health=health, state=state, live=live,
                        last_seen=ts(at(o.get("last_seen", -4)) if "last_seen" in o else t - timedelta(seconds=4)),
                        counts=dict(up=checks - down - warning - unknown, warning=warning, down=down, unknown=unknown)))
    out.sort(key=lambda e: (SEVERITY[e["health"]], e["name"]))
    return out


def observer_name(oid):
    return next(o[1] for o in OBSERVERS if o[0] == oid)


def attention_value(sc):
    items = []
    for a in sc["attention"]:
        parts = a["title"].split(" → ")
        oname = observer_name(a["observer"]) if a["observer"] else ""
        route = parts[1:] if len(parts) > 1 and parts[0] == oname else parts
        items.append(dict(kind=a["kind"], id=a["id"], title=a["title"], route=route, observer=a["observer"],
                          observer_name=oname, since=ts(at(a["since"])) if "since" in a else None,
                          health=a["health"], state=a["state"]))
    return dict(total=sc["attention_total"], items=items)


def service_health(sc, sid):
    if sid in UNMONITORED:
        return "unknown"
    return sc["services"].get(sid, "up")


def application_entries(sc):
    out = []
    for aid, name, svcs in APPS:
        services, counts = [], dict(up=0, warning=0, down=0, unknown=0)
        attention = unmonitored = 0
        for sid, sname in svcs:
            h = service_health(sc, sid)
            monitored = sid not in UNMONITORED
            services.append(dict(id=sid, name=sname, health=h, monitored=monitored, affected=False))
            counts[{"up": "up", "degraded": "warning", "down": "down", "unknown": "unknown"}[h]] += 1
            if not monitored:
                unmonitored += 1
            elif h != "up":
                attention += 1
        hs = [s["health"] for s in services]
        health = "degraded" if any(h in ("down", "degraded") for h in hs) else "unknown" if "unknown" in hs else "up"
        out.append(dict(id=aid, name=name, environment="", health=health, services=services, counts=counts,
                        attention=attention, unmonitored=unmonitored))
    return out


def server_card(sc, node, t, valid):
    s = SERVERS[node]
    over = sc["servers"].get(node, {})
    sampled = t - timedelta(seconds=4)
    cpu, mem, disk = s["cpu"], s["mem"], s["disk"]
    resource = dict(
        check=s["check"], observer=s["observer"], health="up", freshness="fresh",
        sampled_at=ts(sampled), valid_until=ts(sampled + timedelta(seconds=30)),
        cpu=dict(percent=cpu[0], limit=cpu[1], logical=cpu[2]),
        memory=dict(percent=mem[0], limit=mem[1], used_bytes=mem[2], total_bytes=mem[3],
                    basis="free + inactive + speculative"),
        disk=dict(percent=disk[0], limit=disk[1], path="/", used_bytes=disk[2], total_bytes=disk[3]),
        process=dict(name=s["process"][0], matching=s["process"][1]) if s["process"] else None)
    services = []
    for sid in s["services"]:
        h = over.get("services", {}).get(sid, "up" if sid not in UNMONITORED else "unknown")
        services.append(dict(id=sid, name=SERVICE_NAMES[sid], health=h, monitored=sid not in UNMONITORED,
                             affected=sid in over.get("affected", set())))
    services.sort(key=lambda v: SEVERITY[v["health"]])
    observes = [e for e in observer_entries(sc, t) if e["node"] == node]
    return dict(id=node, name=s["name"], kind=s["kind"], provider=s["provider"], group="", where=s["where"],
                health=over.get("health", "up"), note=over.get("note", ""), resources=[resource], services=services,
                observes=observes)


def row(template, value, text, health, t, valid, reason=None, freshness="fresh"):
    r = dict(template)
    r.update(value=value, text=text, health=health, freshness=freshness)
    if reason:
        r["reason"] = reason
    if value is not None:
        r["sampled_at"] = ts(t - timedelta(seconds=4))
        r["valid_until"] = ts(valid)
    return r


def frame(key, seq, t, rows, lifecycle="running", **extra):
    f = dict(schema=1, name="stream", request_id="fixture", config_revision="fx-" + key, instance="fixture-" + key,
             sequence=seq, source="client", project="homelab", observer="", lifecycle=lifecycle,
             generated_at=ts(t), publisher_expires_at=ts(t + timedelta(seconds=30)), title="Topophany", icon="",
             bar_row="status", rows=rows)
    f.update(extra)
    return f


def running(key, sc, seq, t, extra_rows=()):
    valid = t + timedelta(seconds=15)
    v = sc["verdict"]
    seen = observer_entries(sc, t)
    bad = [e for e in seen if e["health"] != "up"]
    att = attention_value(sc)
    apps = application_entries(sc)
    rows = [
        row(ROWS[0], dict(state=v[0], glyph=v[1], text=v[2], counts=dict(v[3], paused=0, maintenance=0),
                          configured=sum(v[3].values()), incidents=v[4],
                          observers=dict(live=sum(1 for e in seen if e["live"]), all=len(seen))),
            v[2], WORD.get(v[0], "unknown"), t, valid),
        row(ROWS[1], seen, "%d of %d see a problem" % (len(bad), len(seen)), worst(e["health"] for e in seen), t, valid),
        row(ROWS[2], att, "%d need attention" % att["total"], worst(i["health"] for i in att["items"]), t, valid),
        row(ROWS[3], apps, "%d applications" % len(apps), worst(a["health"] for a in apps), t, valid),
    ]
    for tpl in ROWS[4:]:
        card = server_card(sc, tpl["select"]["node"], t, valid)
        rows.append(row(tpl, card, card["health"], card["health"], t, valid))
    rows += list(extra_rows)
    return frame(key, seq, t, rows)


def unavailable(key, seq, t, reason="source_unavailable"):
    rows = [row(tpl, None, "unknown", "unknown", t, None, reason=reason, freshness="unavailable") for tpl in ROWS]
    return frame(key, seq, t, rows)


def write(name, frames):
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, name + ".ndjson"), "w", encoding="utf-8") as f:
        for fr in frames:
            line = json.dumps(fr, ensure_ascii=False, separators=(",", ":"))
            assert len(line.encode()) <= 1 << 20
            f.write(line + "\n")


def live_series(key, sc, start=-20, end=50, extra_rows=()):
    return [running(key, sc, i + 1, at(s), extra_rows) for i, s in enumerate(range(start, end + 1, 10))]


def main():
    # The five panel states. Frames every 10 s, renewing the lease; looped.
    for key, sc in SCENARIOS.items():
        write(key, live_series(key, sc))

    # Offline: the collector can't be read. The last good snapshot, 3 min
    # ago, said all clear; topo keeps renewing its lease with unknown rows.
    clear = SCENARIOS["clear"]
    frames = [running("offline", clear, 1, at(-180))]
    frames += [unavailable("offline", i + 2, at(s)) for i, s in enumerate(range(-175, 51, 10))]
    write("offline", frames)

    # Stale: topo stops writing after ANCHOR. Its lease lapses 30 s later.
    inc = SCENARIOS["incidents"]
    write("stale", [running("stale", inc, i + 1, at(s)) for i, s in enumerate(range(-60, 1, 10))])

    # Stopped: topo writes its final frame, with no values, and exits.
    frames = [running("stopped", inc, i + 1, at(s)) for i, s in enumerate(range(-30, 1, 10))]
    frames.append(frame("stopped", len(frames) + 1, at(5), [], lifecycle="stopped"))
    write("stopped", frames)

    # An error frame: a refused request line. The previous request keeps
    # running and its frames keep coming.
    frames = live_series("error", clear, -20, 0)
    err = frame("error", 0, at(5), [], lifecycle="error",
                error=dict(code="invalid_request", message="row attention: limit must be 1..20"))
    err["request_id"] = "fixture-refused"
    del err["sequence"]
    frames.append(err)
    frames += [running("error", clear, len(frames) + i, at(s)) for i, s in enumerate(range(10, 51, 10))]
    write("error-frame", frames)

    # An unknown node: a pinned server that isn't in the topology.
    missing = dict(id="server-3", label="", metric="server.card", visual="card", select={"node": "old-box"},
                   value=None, text="unknown", health="unknown", freshness="unavailable", reason="entity_missing")
    write("unknown-node", live_series("unknown-node", clear, extra_rows=[missing]))


if __name__ == "__main__":
    main()
