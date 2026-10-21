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
# Every node with a card in the Servers tab (servers.list), in its order:
# id, name, kind, provider, where.
LISTED = [
    ("macbook", "MacBook Pro", "laptop", "Home", "Seattle"),
    ("seattle-pc", "Windows Desktop", "desktop", "Home", "Seattle"),
    ("router", "Home Router", "router", "Home", "Seattle"),
    ("sj-vultr", "Vultr San Jose", "host", "Vultr", "San Jose"),
    ("bwh-la", "BandwagonHost LA", "host", "BandwagonHost", "Los Angeles"),
    ("oracle-la", "Oracle LA", "host", "Oracle", "Los Angeles"),
    ("hnl-vultr", "Vultr Honolulu", "host", "Vultr", "Honolulu"),
    ("oracle-ny", "Oracle New York", "host", "Oracle", "New York"),
    ("azure-ny", "Azure New York", "host", "Azure", "New York"),
    ("fra-hetzner", "Hetzner Frankfurt", "host", "Hetzner", "Frankfurt"),
    ("tokyo-vps", "GCP Tokyo", "host", "GCP", "Tokyo"),
    ("cloudflare", "Cloudflare", "edge", "Cloudflare", "anycast"),
    ("vercel", "Vercel", "edge", "Vercel", "anycast"),
    ("supabase", "Supabase", "platform", "Supabase", "Tokyo"),
]
SERVICE_NAMES = {sid: name for _, _, svcs in APPS for sid, name in svcs}
SERVICE_NAMES["topo-worker"] = "Topophany worker"
# The node each service runs on, for services.list and service.card.
SERVICE_HOSTS = {sid: node for node, s in SERVERS.items() for sid in s["services"]}
SERVICE_HOSTS.update({"gitea": "fra-hetzner", "restic": "fra-hetzner", "nextcloud": "oracle-la", "immich": "oracle-la",
                      "vaultwarden": "azure-ny", "syncthing": "oracle-la", "jellyfin": "seattle-pc",
                      "ssh-bastion": "sj-vultr", "workers-api": "cloudflare", "pages": "cloudflare",
                      "r2-gateway": "cloudflare", "queue": "cloudflare"})

# Service cards, as topo preview's homelab draws them: who checks each
# service from where, its latency over the day and its share up. Per check:
# observer, check ID, kind, endpoint, p50 and p95 ms, share up, colo and
# first byte. A scenario says which checks fail, and how.
SERVICE_CARDS = {
    "vless-entry": dict(
        app=("proxy", "Proxy chain"), reason="all checks in this view pass",
        checks=[("seattle-windows", "w-entry-443", "BandwagonHost entry port", "tls", "entry", 46, 50, 98.3, "", ""),
                ("san-jose", "r-entry-443", "Relay contrast BandwagonHost 443", "tls", "entry", 17, 18, 97.6, "", ""),
                ("ny-oracle", "s-entry-443", "Overseas contrast BandwagonHost 443", "tls", "entry", 113, 124, 98.6, "", ""),
                ("frankfurt", "j-entry-443", "Remote entry 443", "tls", "entry", 266, 289, 99.0, "", "")],
        endpoints=[("entry", "public", "192.0.2.10:443", [])],
        depends=[], used_by=["exit-a", "exit-b"], runbook="https://wiki.example.invalid/runbooks/entry",
        memo="Primary entry for the proxy chain. Some networks block it now and then; the Azure entry is the fallback."),
    "main-site": dict(
        app=("site", "Main site"), reason="all checks in this view pass",
        checks=[("san-jose", "r-app-web", "Relay to app web", "http", "app-web", 231, 272, 97.6, "SJC", "origin p50 99 ms · p95 128 ms"),
                ("ny-oracle", "s-web-local", "App web local", "http", "app-web-local", 51, 80, 98.6, "", ""),
                ("frankfurt", "j-blog", "Visitor to app blog", "http", "app-web", 319, 358, 98.6, "FRA", "origin p50 123 ms · p95 152 ms")],
        endpoints=[("app-web", "public", "https://www.example.invalid/", [("cloudflare", "Cloudflare", "edge", "Cloudflare")]),
                   ("app-web-local", "loopback", "http://127.0.0.1:8080/", [])],
        depends=[("postgres", "PostgreSQL", "PostgreSQL Container")], used_by=[],
        answered=dict(pops=["SJC 50%", "FRA 50%"], cache=["DYNAMIC 100%"]),
        runbook="https://wiki.example.invalid/runbooks/blog",
        memo="The public blog. Cloudflare in front, Caddy on the Oracle box behind it; posts live in Postgres."),
    "workers-api": dict(
        app=("serverless", "Serverless"), runtime="workers", reason="all checks in this view pass",
        checks=[("frankfurt", "j-worker", "Workers API", "http", "worker", 54, 79, 99.0, "FRA", ""),
                ("san-jose", "r-worker", "Relay to Workers API", "http", "worker", 54, 84, 97.2, "SJC", "")],
        endpoints=[("worker", "public", "https://api.example.invalid/healthz", [])],
        depends=[], used_by=[], answered=dict(pops=["FRA 51%", "SJC 49%"], cache=[]),
        runbook="", memo="A Worker with a KV store."),
    "nightly-backup": dict(
        app=("code", "Code & backups"), reason="registered, not monitored", checks=[], endpoints=[],
        depends=[("restic", "Restic Backups", "Hetzner Frankfurt")], used_by=[], runbook="",
        memo="Registered only; it doesn't fake heartbeats without real receipts."),
}
SLOTS = 36

# The map (map.graph), as View.Graph() draws topo preview's homelab: every
# node with where it is, then the colos Cloudflare answered from. Per node:
# id, name, kind, group, provider, parent, place, lat, lon. A node without
# coordinates has no location; one with a parent and none of its own is
# placed at its parent's.
MAP_NODES = [
    ("seattle-pc", "Windows Desktop", "desktop", "home", "Home", "", "Seattle", 47.61, -122.33),
    ("macbook", "MacBook Pro", "laptop", "home", "Home", "", "Seattle", 47.61, -122.33),
    ("router", "Home Router", "router", "home", "Home", "", "Seattle", 47.61, -122.33),
    ("sj-vultr", "Vultr San Jose", "host", "relay", "Vultr", "", "San Jose", 37.34, -121.89),
    ("bwh-la", "BandwagonHost LA", "host", "transit", "BandwagonHost", "", "Los Angeles", 34.05, -118.24),
    ("oracle-la", "Oracle LA", "host", "exit", "Oracle", "", "Los Angeles", 33.99, -118.31),
    ("hnl-vultr", "Vultr Honolulu", "host", "exit", "Vultr", "", "Honolulu", 21.31, -157.86),
    ("oracle-ny", "Oracle New York", "host", "self-hosted", "Oracle", "", "New York", 40.71, -74.01),
    ("postgres-box", "PostgreSQL Container", "container", "self-hosted", "", "oracle-ny", "", None, None),
    ("azure-ny", "Azure New York", "host", "self-hosted", "Azure", "", "New York", 40.73, -73.94),
    ("tokyo-vps", "GCP Tokyo", "host", "self-hosted", "GCP", "", "Tokyo", 35.68, 139.77),
    ("openlist", "OpenList", "container", "self-hosted", "", "tokyo-vps", "", None, None),
    ("fra-hetzner", "Hetzner Frankfurt", "host", "self-hosted", "Hetzner", "", "Frankfurt", 50.11, 8.68),
    ("cloudflare", "Cloudflare", "edge", "edge", "Cloudflare", "", "", None, None),
    ("vercel", "Vercel", "edge", "edge", "Vercel", "", "", None, None),
    ("supabase", "Supabase", "platform", "edge", "Supabase", "", "Tokyo", 35.68, 139.77),
    ("internet", "Internet", "external", "external", "", "", "", None, None),
    ("visitors", "Visitors", "external", "external", "", "", "", None, None),
]
# Colos the edge in front named in fresh checks: (code, city, lat, lon,
# the observer's node).
MAP_COLOS = [("SJC", "San Jose", 37.36, -121.93, "sj-vultr"), ("FRA", "Frankfurt", 50.03, 8.56, "fra-hetzner")]
# Declared links: id, from, to, and the signal of each when the scenario
# says nothing. Unmeasured links over a passing path are carried.
MAP_LINKS = [
    ("win-transit", "seattle-pc", "bwh-la", "up"), ("mac-transit", "macbook", "bwh-la", "up"),
    ("win-aux", "seattle-pc", "azure-ny", "up"), ("mac-aux", "macbook", "azure-ny", "up"),
    ("transit-exit-a", "bwh-la", "oracle-la", "up"), ("transit-exit-b", "bwh-la", "hnl-vultr", "up"),
    ("aux-exit-a", "azure-ny", "oracle-la", "up"), ("aux-exit-b", "azure-ny", "hnl-vultr", "up"),
    ("exit-a-net", "oracle-la", "internet", "carried"), ("exit-b-net", "hnl-vultr", "internet", "carried"),
    ("win-router", "seattle-pc", "router", "up"), ("mac-router", "macbook", "router", "up"),
    ("relay-win", "sj-vultr", "seattle-pc", "up"), ("visitors-relay", "visitors", "sj-vultr", "carried"),
    ("visitors-cf", "visitors", "cloudflare", "carried"), ("cf-app", "cloudflare", "oracle-ny", "up"),
    ("visitors-jp", "visitors", "tokyo-vps", "carried"), ("visitors-git", "visitors", "fra-hetzner", "carried"),
    ("visitors-vercel", "visitors", "vercel", "carried"), ("vercel-supabase", "vercel", "supabase", "carried"),
    ("app-git", "oracle-ny", "fra-hetzner", "up"), ("home-cf", "seattle-pc", "cloudflare", "up"),
]
# Hops implied by declared paths that no link declares: id, from, to,
# observer.
MAP_PATHS = [("path:relay-entry", "sj-vultr", "bwh-la", "san-jose")]
# Per scenario: node healths and affected nodes, and edge signals.
MAP_SCENARIOS = {
    "clear": dict(nodes={}, affected=set(), edges={"path:relay-entry": "carried"}),
    "degraded": dict(nodes={}, affected={"bwh-la"},
                     edges={"mac-transit": "degraded", "win-transit": "affected", "transit-exit-a": "affected",
                            "path:relay-entry": "carried"}),
    "incidents": dict(nodes={"bwh-la": "degraded"}, affected={"bwh-la", "oracle-la", "hnl-vultr"},
                      edges={"win-transit": "down", "mac-transit": "down", "transit-exit-a": "affected",
                             "transit-exit-b": "affected", "exit-a-net": "affected", "exit-b-net": "affected",
                             "path:relay-entry": "down"}),
    "incomplete": dict(nodes={"hnl-vultr": "unknown"}, affected=set(),
                       edges={"transit-exit-b": "unknown", "aux-exit-b": "unknown", "exit-b-net": "unknown",
                              "path:relay-entry": "carried"}),
}

# --------------------------------------------------------------- scenarios

# Per scenario: observer overrides (counts and liveness), service healths,
# attention entries, server overrides and the verdict.
SCENARIOS = {
    "clear": dict(
        verdict=("clear", "●", "ALL CLEAR", dict(up=68, warning=0, down=0, unknown=0), 0),
        observers={}, services={}, attention=[], attention_total=0, servers={}, checks={}),
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
        attention_total=2, servers={}, checks={"w-entry-443": ("policy", 14)}),
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
                                affected={"vless-entry", "exit-a", "relay"})},
        checks={"w-entry-443": ("fail", 24), "r-entry-443": ("fail", 24)}),
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
        attention_total=2, servers={}, checks={}),
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
    dict(id="service-1", label="", metric="service.card", visual="card", select={"service": "vless-entry"}),
    dict(id="service-2", label="", metric="service.card", visual="card", select={"service": "main-site"}),
    dict(id="service-3", label="", metric="service.card", visual="card", select={"service": "workers-api"}),
    dict(id="service-4", label="", metric="service.card", visual="card", select={"service": "nightly-backup"}),
    dict(id="services", label="", metric="services.list", visual="list", select={}),
    dict(id="map", label="", metric="map.graph", visual="map", select={}),
    dict(id="servers", label="", metric="servers.list", visual="list", select={}),
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


def listed(node):
    return next(l for l in LISTED if l[0] == node)


def slots(check, p50, failing):
    """The newest SLOTS samples, oldest first: passing ones near the median,
    one failure in the history, and the scenario's failures at the end."""
    seed = sum(ord(c) * (i + 7) for i, c in enumerate(check))
    out = []
    for i in range(SLOTS):
        seed = (seed * 1103515245 + 12345) % (1 << 31)
        jitter = 0.84 + 0.34 * (seed % 1000) / 1000
        out.append(dict(outcome="ok", elapsed_ms=max(1, round(p50 * jitter))))
    out[seed % 9 + 6] = dict(outcome="fail")
    if failing:
        outcome, n = failing
        for i in range(SLOTS - n, SLOTS):
            out[i] = dict(outcome=outcome)
    return out


def service_card(sc, sid, t):
    d = SERVICE_CARDS[sid]
    host = listed(SERVICE_HOSTS[sid])
    sampled = t - timedelta(seconds=4)
    by = {}
    order = []
    for oid, cid, name, kind, ep, p50, p95, up, colo, first in d["checks"]:
        failing = sc["checks"].get(cid)
        health = {"fail": "down", "policy": "degraded"}[failing[0]] if failing else "up"
        check = dict(id=cid, name=name, kind=kind, endpoint=ep, health=health, freshness="fresh",
                     sampled_at=ts(sampled), valid_until=ts(sampled + timedelta(seconds=30)),
                     latency=dict(p50_ms=p50, p95_ms=p95), up_24h=up, first_byte=first, colo=colo,
                     samples=dict(interval_seconds=10, slots=slots(cid, p50, failing)))
        if oid not in by:
            by[oid] = []
            order.append(oid)
        by[oid].append(check)
    places = {}
    for oid in order:
        node = next(o[2] for o in OBSERVERS if o[0] == oid)
        places[oid] = listed(node)[4]
    seen = []
    for oid in order:
        checks = sorted(by[oid], key=lambda c: SEVERITY[c["health"]])
        shared = sum(1 for o in order if places[o] == places[oid]) > 1
        name = observer_name(oid)
        label = name.replace(places[oid], "").strip() if shared else places[oid]
        seen.append(dict(observer=dict(id=oid, name=name), label=label, health=checks[0]["health"], checks=checks))
    seen.sort(key=lambda o: SEVERITY[o["health"]])
    healths = [c["health"] for o in seen for c in o["checks"]]
    monitored = bool(d["checks"])
    health = worst(healths) if monitored else "unknown"
    if monitored and health != "up" and "up" in healths:
        health = "degraded"
    reason = d["reason"] if health == "up" or not monitored else "some access checks pass; others fail, degrade or lack current evidence"
    endpoints = []
    for eid, network, address, via in d["endpoints"]:
        hs = [c["health"] for o in seen for c in o["checks"] if c["endpoint"] == eid]
        endpoints.append(dict(id=eid, network=network, address=address, health=worst(hs) if hs else "",
                              via=[dict(id=i, name=n, kind=k, provider=pr) for i, n, k, pr in via]))
    return dict(id=sid, name=SERVICE_NAMES[sid], application=dict(id=d["app"][0], name=d["app"][1]), environment="",
                runtime=d.get("runtime", ""), health=health, note="", evidence="inferred" if monitored else "unknown",
                reason=reason, monitored=monitored,
                host=dict(id=host[0], name=host[1], kind=host[2], provider=host[3], where=host[4],
                          health=sc["servers"].get(host[0], {}).get("health", "up")),
                seen_from=seen, endpoints=endpoints, answered_from=d.get("answered"),
                depends_on=[dict(id=i, name=n, health="up", affected=False, monitored=True, host=h) for i, n, h in d["depends"]],
                used_by=[dict(id=i, name=SERVICE_NAMES[i], health=service_health(sc, i), affected=False, monitored=True,
                              host=listed(SERVICE_HOSTS[i])[1]) for i in d["used_by"]],
                runbook=d["runbook"], memo=d["memo"])


def service_entries(sc):
    out = []
    for _, app, svcs in APPS:
        for sid, name in svcs:
            host = listed(SERVICE_HOSTS[sid])
            out.append(dict(id=sid, name=name, application=app, health=service_health(sc, sid), note="",
                            monitored=sid not in UNMONITORED,
                            host=dict(id=host[0], name=host[1], kind=host[2], provider=host[3])))
    return out


def server_entries(sc):
    out = []
    for node, name, kind, provider, where in LISTED:
        over = sc["servers"].get(node, {})
        out.append(dict(id=node, name=name, kind=kind, provider=provider, group="", where=where,
                        health=over.get("health", "up"), note=over.get("note", "")))
    return out


def map_graph(key):
    """map.graph for a scenario, as View.Graph() writes it."""
    sc = MAP_SCENARIOS[key]
    by = {n[0]: n for n in MAP_NODES}
    nodes = []
    for nid, name, kind, group, provider, parent, place, lat, lon in MAP_NODES:
        inherited = lat is None and parent in by and by[parent][7] is not None
        if inherited:
            place, lat, lon = by[parent][6], by[parent][7], by[parent][8]
        health = sc["nodes"].get(nid, "unknown" if kind == "external" else "up")
        affected = nid in sc["affected"]
        signal = "affected" if affected and health in ("up", "unknown") else health
        nodes.append(dict(id=nid, name=name, kind=kind, group=group, provider=provider, parent=parent, place=place,
                          lat=lat, lon=lon, located=lat is not None, inherited=inherited, health=health,
                          affected=affected, signal=signal))
    edges = []
    for lid, a, b, signal in MAP_LINKS:
        edges.append(dict(id=lid, **{"from": a}, to=b, kind="link", signal=sc["edges"].get(lid, signal), observer=""))
    for pid, a, b, observer in MAP_PATHS:
        edges.append(dict(id=pid, **{"from": a}, to=b, kind="path", signal=sc["edges"].get(pid, "carried"), observer=observer))
    for nid, _, _, _, _, parent, _, _, _ in MAP_NODES:
        if parent:
            edges.append(dict(id="parent:" + nid, **{"from": parent}, to=nid, kind="contains", signal="unknown", observer=""))
    for code, city, lat, lon, observer in MAP_COLOS:
        cid = "colo:cloudflare:" + code
        nodes.append(dict(id=cid, name=code, kind="colo", group="", provider="Cloudflare", parent="", place=city, lat=lat,
                          lon=lon, located=True, inherited=False, health="unknown", affected=False, signal="carried"))
        edges.append(dict(id=cid + ":to", **{"from": cid}, to="cloudflare", kind="colo", signal="carried", observer=""))
        edges.append(dict(id=cid + ":from:" + observer, **{"from": observer}, to=cid, kind="colo", signal="carried", observer=""))
    return dict(nodes=nodes, edges=edges)


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
    for tpl in ROWS[4:7]:
        card = server_card(sc, tpl["select"]["node"], t, valid)
        rows.append(row(tpl, card, card["health"], card["health"], t, valid))
    for tpl in ROWS[7:11]:
        card = service_card(sc, tpl["select"]["service"], t)
        rows.append(row(tpl, card, card["health"], card["health"], t, valid))
    services = service_entries(sc)
    rows.append(row(ROWS[11], services, "%d services" % len(services), worst(e["health"] for e in services), t, valid))
    rows += list(extra_rows)
    graph = map_graph(next(k for k, v in SCENARIOS.items() if v is sc))
    places = {n["place"] for n in graph["nodes"] if n["located"]}
    rows.append(row(ROWS[-2], graph, "%d nodes in %d places" % (len(graph["nodes"]), len(places)),
                    worst(n["health"] for n in graph["nodes"]), t, valid))
    listed = server_entries(sc)
    rows.append(row(ROWS[-1], listed, "%d servers" % len(listed), worst(s["health"] for s in listed), t, valid))
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
