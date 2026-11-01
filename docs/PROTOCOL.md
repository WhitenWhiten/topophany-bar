# `topo monitor stream`: protocol 1

This is the contract between `topo` (the producer, in the topophany repository) and topophany-bar (the consumer). It is authoritative: where `design/DESIGN.md` and this file differ, this file wins. A change to it needs both sides.

The stream reuses the `topo monitor` panel format (template schema 1, panel output schema 1). The additions are marked **new**.

## 1. The process

```
topo monitor stream                 # requests on stdin, frames on stdout
topo monitor stream --capabilities  # one JSON line describing what this topo supports, then exit 0
topo monitor stream --profiles      # one JSON line listing the saved client profiles, then exit 0 (new)
```

- **stdin:** requests, one JSON object per line (NDJSON, UTF-8). A line may be at most 256 KiB; a longer one is an `invalid_request`, and the stream keeps reading.
- **stdout:** frames, one JSON object per line, at most 1 MiB each. Nothing else is ever written to stdout.
- **stderr:** short human-readable diagnostics, one per line, never secrets, raw upstream errors or tokens. Consumers may show them; they must not parse them.
- **Files:** the process writes none (no output file, no lock). It reads only the client credential file, and only for `source: "client"`.

Lifecycle:

1. **Start.** Wait for the first request. No frames are written before one arrives.
2. **A valid request:** write a frame at once, then keep writing per section 4.
3. **Another valid request line:** replace the running request atomically, with a new `config_revision` and the new `request_id`, and write a frame at once.
4. **An invalid request line:** write an error frame (section 3.2) and leave the previous request running, if there is one.
5. **stdin reaches EOF, or SIGINT/SIGTERM:** write one final frame with `lifecycle: "stopped"` and no values, then exit 0.
6. **stdout is closed (EPIPE):** exit 0 without writing anything else.

Exit codes:

- **0** in every runtime case above;
- **2** only for invalid command-line flags.

Bad requests, unreachable collectors and credential problems never end the process.

### Capabilities

`--capabilities` prints one line:

```json
{"protocol":1,"version":"1.3.0","sources":["client","preview"],
 "visuals":["text","bar","status","list","card","map"],
 "metrics":[{"name":"summary.verdict","type":"object","sources":["client","collector"],"visual":"status"}, …],
 "profiles":true}
```

`metrics` is the catalog `topo monitor metrics` prints, plus each metric's allowed `visual`. A consumer checks `protocol == 1` and the metrics it needs before it starts a stream. A `topo` without this subcommand exits non-zero, and the consumer says that `topo` must be upgraded.

**`profiles` (new):** `true` when this `topo` serves `--profiles`. A consumer runs `--profiles` only then; absent means `false`.

### Profiles (new)

`--profiles` prints one line, for choosing the `profile` a request names:

```json
{"profiles":[{"name":"home","project":"homelab","active":true},{"name":"work","project":"","active":false}]}
```

- **One entry per profile `topo login` saved,** in the order `topo` lists them, at most 64.
- **`name`** is what a request's `profile` takes. **`project`** is the project the profile was saved for, or `""` when it records none. **`active`** is `true` for the profile `""` selects, and for no other.
- **Names and projects only:** never tokens, server URLs, usernames or file paths.
- **`--credentials PATH`** reads that credential file instead, as a request's `credentials` does. Otherwise discovery is `topo`'s normal one.
- **No credential file, or no profiles in it:** `{"profiles":[]}`, exit 0. A credential file that can't be read or parsed is also an empty list and exit 0, with one line on stderr.

## 2. Requests

```json
{
  "schema": 1,
  "request_id": "settings-42",
  "source": "client",
  "credentials": "",
  "profile": "",
  "project": "",
  "observer": "",
  "interval": "5s",
  "template": { "schema": 1, "title": "Topophany", "bar": { "row": "status" }, "rows": [ … ] }
}
```

| Field | Type | Meaning |
|---|---|---|
| `schema` | int, required | `1` |
| `request_id` | string, ≤ 64 bytes | Echoed in every frame for this request, so the consumer can tell when a new request took effect. |
| `source` | `"client"` (default) or `"preview"` | `client` reads a collector through saved credentials, as `topo` does. `preview` reads `topo preview`'s synthetic evidence and needs no collector or credentials. |
| `credentials` | absolute path or `""` | Credential file; `""` uses `topo`'s normal discovery. `client` only. |
| `profile` | string | Saved profile; `""` uses the active profile. `client` only. |
| `project` | string | When set, a snapshot from another project is refused (`project_mismatch`). |
| `observer` | string | The view, as `topo --observer`; `""` is all observers. |
| `scenario` | int ≥ 0 | `preview` only: the scenario as `topo preview scenarios` numbers them. `0` is the calm network. |
| `lang` | `"en"`, `"ja"` or `"zh"` | `preview` only: the language of the built-in network. Default `"en"`. |
| `interval` | duration, `1s` to `1h` | Display cadence, as `topo monitor configure --interval`. Default `5s`. |
| `template` | template schema 1 | What to compute; see 2.1. |

### 2.1 Template additions (new)

The template is `topo monitor`'s schema 1, validated as today, with these additions:

- **Row field `limit`:** an int, 1 to 20; default 5; only for `attention.list`.
- **Selector `node`:** a topology node ID (`config.ID`); only for `server.card`, where it is required.
- **Selector `service`:** a topology service ID; only for `service.card`, where it is required.
- **New visuals:** `status`, `list`, `card` and `map`. Each metric allows exactly one visual (table below); `text` and `bar` keep their meaning for the existing metrics.
- **`bar.row`:** must still reference a row. The consumer points it at the `summary.verdict` row.

| Metric (new) | Visual | Selector | Sources |
|---|---|---|---|
| `summary.verdict` | `status` | none | client, collector, preview |
| `observers.verdicts` | `list` | none | client, collector, preview |
| `attention.list` | `list` | none (`limit`) | client, collector, preview |
| `applications.list` | `list` | none | client, collector, preview |
| `server.card` | `card` | `node` (required) | client, collector, preview |
| `servers.list` (new) | `list` | none | client, collector, preview |
| `service.card` (new) | `card` | `service` (required) | client, collector, preview |
| `services.list` (new) | `list` | none | client, collector, preview |
| `map.graph` (new) | `map` | none | client, collector, preview |

The existing metrics (`summary.status`, `check.status`, `host.*`, …) remain valid in stream requests with their current sources. `preview` behaves as `client` for source checks.

## 3. Frames

### 3.1 Normal frames

This is the panel output schema 1 that `topo monitor` already writes:

```json
{
  "schema": 1, "name": "stream", "request_id": "settings-42",
  "config_revision": "…", "instance": "…", "sequence": 1842,
  "source": "client", "project": "homelab", "observer": "",
  "lifecycle": "running",
  "generated_at": "2026-10-18T13:30:37Z", "publisher_expires_at": "2026-10-18T13:31:07Z",
  "title": "Topophany", "icon": "", "bar_row": "status",
  "rows": [ { …row… } ]
}
```

- **`name`** is always `"stream"`.
- **`request_id`** is **new**.
- **`lifecycle`** is `running`, `error` or `stopped`.
- **`sequence`** increases within an `instance` and may skip.

Every row keeps its template fields and adds the fields every row has today:

- `value`, `unit` and `text`;
- `health`: `up`, `degraded`, `down` or `unknown`;
- `freshness` and `reason`;
- `sampled_at`, the newest underlying sample;
- `valid_until`, the earliest deadline among the evidence the value relies on.

When the collector can't be read, the frame is still `running`. Its rows have `value: null`, `health: "unknown"`, `freshness: "unavailable"` and `reason: "source_unavailable"`, exactly as `topo monitor run` behaves today.

### 3.2 Error frames (new)

```json
{"schema":1,"name":"stream","request_id":"settings-43","lifecycle":"error",
 "error":{"code":"invalid_request","message":"row attention: limit must be 1..20"},
 "generated_at":"…","publisher_expires_at":"…","rows":[]}
```

Error codes:

| Code | When |
|---|---|
| `invalid_request` | A malformed line, an unknown field value, or a template that fails validation. |
| `unsupported_protocol` | `schema` isn't 1. |
| `credentials_unavailable` | The credential file can't be read. |
| `profile_not_found` | The profile isn't in the credential file. |
| `project_mismatch` | The snapshot's project differs from `project`. |

An error frame has no rows. The consumer keeps showing the last `running` frame, subject to its deadlines (section 5). An error never stops a previously valid request.

### 3.3 Row values for the new metrics

All times are RFC 3339 UTC. Every count is an integer ≥ 0. Every percentage is a number from 0 to 100, or `null` when unknown. Names are the topology's display names (the ID when a name is unset).

#### `summary.verdict`

```json
{"state":"incidents","glyph":"✖","text":"5 INCIDENTS",
 "counts":{"up":63,"warning":0,"down":5,"unknown":0,"paused":0,"maintenance":0},
 "configured":68,"incidents":5,"observers":{"live":11,"all":11}}
```

- **`state`, `glyph`, `text`:** from `view.Verdict()`. `state` is one of `clear`, `degraded`, `incidents`, `down`, `incomplete`, `no-evidence`, `no-checks` or `cached`.
- **`counts`:** `up`, `warning`, `down` and `unknown` are `View.Counts()`. `paused` and `maintenance` are **subsets of `unknown`**: how many of the unknown checks are paused or in maintenance. They are never added to the total.
- **`configured`:** `up + warning + down + unknown`, every check in the view. For example, three checks that are up, paused and in maintenance give `up 1, unknown 2, paused 1, maintenance 1, configured 3`.
- **`observers`:** `View.Live()`.
- **The row's `health`:**
  - `clear` → `up`;
  - `degraded` → `degraded`;
  - `incidents` and `down` → `down`;
  - every other state → `unknown`.
- **The row's `text`:** `text`.

#### `observers.verdicts`

```json
[{"id":"seattle-macbook","name":"Seattle MacBook","node":"macbook","health":"down","state":"incidents",
  "live":true,"last_seen":"2026-10-18T13:30:33Z","counts":{"up":13,"warning":0,"down":1,"unknown":0}}]
```

- **One entry per observer in the view,** at most 64.
- **`state`:** the verdict of that observer's own view, the snapshot as `?observer=<id>` would scope it. `health` maps it as for `summary.verdict`; an observer that isn't live is `unknown`.
- **Order:** `down`, `degraded`, `unknown`, `up`, then by name.
- **The row's `health`:** the worst entry. **`text`:** for example `"3 of 11 see a problem"`.

#### `attention.list`

```json
{"total":17,"items":[
  {"kind":"incident","id":"inc-7f3a","title":"Seattle MacBook → Primary BandwagonHost → Oracle Exit A",
   "route":["Primary BandwagonHost","Oracle Exit A"],"observer":"seattle-macbook","observer_name":"Seattle MacBook",
   "since":"2026-10-18T13:26:02Z","health":"down","state":"open"}]}
```

- **`items`:** the first `limit` entries of the Overview's Needs attention list, in its order (open ledger incidents first, then `view.AttentionRank`). `total` counts the whole list.
- **`kind`:** as `view.Row.Kind`: `incident`, `path`, `service`, `node`, `check`, `observer`, `endpoint` or `link`.
- **`title`:** the TUI's title for the entry.
- **`route`:** `title` split on `" → "`, without a leading element equal to `observer_name`. A single element when the title has no arrows.
- **`observer`, `observer_name`:** the observer the entry was seen from, or `""` when it has none.
- **`since`:** the ledger's `since` for incidents; `null` otherwise.
- **`state`:** the TUI's state word, lowercased.
  - Incidents: `view.Pill(row)`, so `open` or `recovering`.
  - Every other kind: `view.State(row)`, so `down`, `warn`, `unknown`, `affected`, `outdated`, `paused`, `maintenance`, `cached` or `recovering`, and `up` where `State` returns `""`.

  Consumers must accept any lowercase word, and fall back on `health` for one they don't know.
- **The row's `health`:** the worst item's, or `up` when the list is empty in a current view.

#### `applications.list`

```json
[{"id":"proxy","name":"Proxy chain","environment":"","health":"degraded",
  "services":[{"id":"vless-entry","name":"VLESS+Reality Entry (Primary)","health":"degraded","monitored":true,"affected":false}],
  "counts":{"up":3,"warning":3,"down":0,"unknown":0},"attention":3,"unmonitored":0}]
```

- **One entry per application group** as the Services tab groups by application (with `environment` when the topology declares environments). At most 64 entries, with at most 64 services each, in topology order.
- **`health`:** the group's evidence as the TUI computes it (`view/group_evidence.go`). In a cached view, everything is `unknown`.
- **`attention`:** how many services are not up, not counting unmonitored ones. **`unmonitored`:** how many services no check measures.

#### `server.card`

```json
{"id":"oracle-ny","name":"Oracle New York","kind":"host","provider":"Oracle","group":"","where":"New York",
 "health":"up","note":"",
 "resources":[{"check":"oracle-ny-host","observer":"ny-oracle","health":"up","freshness":"fresh",
   "sampled_at":"2026-10-18T13:30:33Z","valid_until":"2026-10-18T13:31:03Z",
   "cpu":{"percent":26.3,"limit":90,"logical":8},
   "memory":{"percent":46.2,"limit":90,"used_bytes":7944011776,"total_bytes":17179869184,"basis":"…"},
   "disk":{"percent":58.4,"limit":90,"path":"/","used_bytes":161061273600,"total_bytes":274877906944},
   "process":{"name":"caddy","matching":1}}],
 "services":[{"id":"main-site","name":"Main Site (Caddy + Blog)","health":"up","monitored":true,"affected":false}],
 "observes":[{"id":"ny-oracle","name":"New York Oracle Cloud","health":"up","state":"clear","live":true,
   "last_seen":"2026-10-18T13:30:33Z","counts":{"up":9,"warning":0,"down":0,"unknown":0}}]}
```

- **Built from `View.Fleet().Card(node)`.**
  - `kind` and `provider` come from the node.
  - `where` is `Card.Where`.
  - `health` and `note` (`affected`, `outdated` or `""`) are the node's state as the Servers tab shows it.
- **`resources`:** one entry per host check on the node (`CardResource`), primary disk first.
  - `limit` is the check's `max_*_percent`, or `null` when the check sets none.
  - Each number is `null` unless the check is `fresh` and its own `valid_until` has not passed. At expiry, set every numeric field (including limits and process matching) to `null`, resource health to `unknown`, and fresh resource freshness to `stale`. Keep the resource entry, `sampled_at`, original `valid_until`, disk path, process name and the rest of the card. A resource deadline alone never expires the whole card.
  - `process` is `null` when the check names no process.
- **`services`:** up to 32 services, trouble first, as `Card.Services`.
- **`observes`:** the observers on this node, each with its own verdict, as in `observers.verdicts`, plus `valid_until` for the checks and heartbeat behind that verdict. At that deadline, retain identity and `last_seen`, set `state: "cached"`, `health: "unknown"`, `live: false`, and move all check counts into `unknown`. This does not expire the rest of the card. Older frames without this field rely on their row deadline.
- **An unknown node:** `value: null`, `health: "unknown"`, `reason: "entity_missing"`.
- **The row's `valid_until`:** the earliest deadline of the source envelope, node state and displayed services, including transitive service dependencies and path dependencies/candidates. Raw resource readings and nested observer verdicts use their own deadlines, not the row deadline. A host check that also supports a service judgment still bounds that judgment.

#### `servers.list` (new)

```json
[{"id":"oracle-ny","name":"Oracle New York","kind":"host","provider":"Oracle","group":"","where":"New York",
  "health":"up","note":""}]
```

- **One entry per node with a card in the Servers tab** (`View.Fleet()`), in that tab's order, at most 256. Every `id` is a valid `server.card` `node`. It's for choosing nodes; a consumer draws a node's card from `server.card`.
- **`name`, `kind`, `provider`, `group`, `where`, `health` and `note`** are as in `server.card`. In a cached view, every `health` is `unknown`.
- **The row's `health`:** the worst entry's. **`text`:** for example `"14 servers"`.
- **The row's `valid_until`:** the earliest deadline of the source envelope and the listed nodes' states, as for `server.card`'s node state.

#### `service.card` (new)

```json
{"id":"blog","name":"Main Site (Caddy + Blog)","application":{"id":"main-site","name":"Main site"},"environment":"","runtime":"",
 "health":"up","note":"","evidence":"inferred","reason":"all checks in this view pass","monitored":true,"elsewhere":false,
 "host":{"id":"app","name":"Oracle New York","kind":"host","provider":"Oracle","where":"New York","health":"up"},
 "seen_from":[{"observer":{"id":"obs-relay","name":"San Jose DigitalOcean"},"label":"San Jose","health":"up",
   "checks":[{"id":"r-app-web","name":"Relay to app web","kind":"http","endpoint":"app-web","health":"up","freshness":"fresh",
     "sampled_at":"2026-10-18T13:30:33Z","valid_until":"2026-10-18T13:31:03Z",
     "latency":{"p50_ms":231,"p95_ms":272},"up_24h":97.6,"first_byte":"origin 98 ms","colo":"SJC",
     "samples":{"interval_seconds":15,"slots":[{"outcome":"ok","elapsed_ms":220},{"outcome":"fail"},{"outcome":"none"}]}}]}],
 "endpoints":[{"id":"app-web","network":"public","address":"https://www.example.invalid/","health":"up",
   "via":[{"id":"cf","name":"Cloudflare","kind":"edge","provider":"Cloudflare"}]}],
 "answered_from":{"pops":["SJC 50%","FRA 50%"],"cache":["DYNAMIC 100%"]},
 "depends_on":[{"id":"postgres","name":"PostgreSQL","health":"up","affected":false,"monitored":true,"host":"PostgreSQL Container"}],
 "used_by":[],"runbook":"https://wiki.example.invalid/runbooks/blog","memo":"The public blog."}
```

- **Built from `View.Fleet().ServiceCard(service)`,** the card the Services tab draws. The app adds nothing: no thresholds, no grouping, no share of its own.
  - `health` and `note` (`affected`, `cached` or `""`) are the service's state as the Services tab shows it. `evidence` and `reason` are its state's own words.
  - `monitored` is `false` when no check measures the service. Then `seen_from` is empty.
  - `elsewhere` is `true` when the view is scoped to one observer and another observer's checks measure the service. With `monitored` `false`, the card says it is not seen from here, not that it is unmonitored.
  - `host` is the node the service runs on, with that node's state as `health`. Its `where` is the node's place: its location's label, its parent's where it has none, `anycast` for an edge, else `""`.
- **`seen_from`:** the service's checks by observer, the observer with the worst check first, at most 8. Each observer's `checks` are worst first, at most 4. `health` is its worst check's.
  - **`label`** is the observer node's place, or, where two observers in the card share a place, the observer's name without it ("Windows"). It is for display; `observer.id` identifies.
  - **`latency`** and **`up_24h`** come from the check's 24 h rollup: the median and 95th percentile of the passing samples, and the share of measured time up. `null` when the rollup has no such samples.
  - **`first_byte`** is `view.FirstByteLine` of that rollup, `""` when there is none. **`colo`** is the colo the edge in front named in the check's newest response: always a string while current, `""` when none, and `null` once withheld at the check's deadline.
  - **`samples`:** always an object with `interval_seconds`. Its `slots` are the check's most recent samples, oldest first, newest last, at most 40: `outcome` is `ok`, `fail`, `policy`, `error`, `unknown` or `none` (no sample taken in that interval), as `view.Strip` lays them out; `elapsed_ms` only for `ok`.
  - **`samples.slots` is `null`** while `topo` holds no samples for the check, as well as after the check's deadline. A consumer draws no samples then, never an empty or `none` strip.
  - **Where the history comes from:** `topo` reads it for at most 4 checks per fetch from a collector (`preview`: all at once), then extends it from each snapshot's newest sample. On a client source, a check's `slots` may be `null` in the first frame or two.
  - **Each check's `valid_until`** is its own, and in a fresh frame never earlier than the row's: the row's deadline covers all of the service's checks. The checks' deadlines matter once a row is held past a renewal (section 5). At a check's deadline, the check's `health` becomes `unknown`, `freshness` becomes `stale`, and `latency`, `up_24h`, `colo` and `samples.slots` are withheld (`null`). Keep its identity, `sampled_at`, the original `valid_until` and the rest of the card. One check's deadline never expires the card.
- **`endpoints`:** how the service is reached, in topology order: `health` is `""` where no check targets the address. `via` is the edges and proxies in front, client side first, each `{id, name, kind, provider}`.
- **`answered_from`:** `pops` and `cache` only: the colos the edge in front answered from over 24 h, at most 6, and the cache statuses it reported, as shares of the service's checks' rollups added up, largest first. A service's colos only come from rollups. `null` when nothing in front names a colo.
- **`depends_on` and `used_by`:** the services this one depends on and those that depend on it, at most 16 each, with their state; `affected` as in `server.card`'s services.
- **An unknown service:** `value: null`, `health: "unknown"`, `reason: "entity_missing"`.
- **The row's `valid_until`:** the earliest deadline of the source envelope, the service's state, its host's state and the displayed dependencies' states. The checks' readings use their own deadlines.

#### `services.list` (new)

```json
[{"id":"blog","name":"Main Site (Caddy + Blog)","application":"Main site","health":"up","note":"","monitored":true,"elsewhere":false,
  "host":{"id":"app","name":"Oracle New York","kind":"host","provider":"Oracle"}}]
```

- **One entry per service,** in the Services tab's order (by application, then topology order), at most 256. Every `id` is a valid `service.card` `service`. It's for choosing services; a consumer draws a service's card from `service.card`.
- **`application`** is the application's name, `""` for none. **`health`, `note`, `monitored` and `elsewhere`** are as in `service.card`. **`host`** is `{id, name, kind, provider}`: `service.card`'s without `where` and `health`. In a cached view, every `health` is `unknown`.
- **The row's `health`:** the worst entry's. **`text`:** for example `"23 services"`.
- **The row's `valid_until`:** the earliest deadline of the source envelope and the listed services' states.

#### `map.graph` (new)

```json
{"nodes":[{"id":"transit","name":"Primary BandwagonHost","kind":"host","group":"transit","provider":"bandwagon","parent":"",
   "place":"Los Angeles","lat":34.05,"lon":-118.24,"located":true,"inherited":false,
   "health":"up","affected":true,"signal":"affected"},
  {"id":"cf","name":"Cloudflare","kind":"edge","group":"edge","provider":"cloudflare","parent":"","place":"",
   "lat":null,"lon":null,"located":false,"inherited":false,"health":"up","affected":false,"signal":"up"}],
 "edges":[{"id":"mac-transit","from":"mac","to":"transit","kind":"link","signal":"down","observer":""},
  {"id":"path:w-transit-exit-a","from":"transit","to":"exit-a","kind":"path","signal":"affected","observer":"obs-win"}]}
```

- **Built from `View.Graph()`,** the nodes and edges the TUI's maps draw. The app adds nothing: no signal, no link and no place of its own.
- **`nodes`:** every topology node, in topology order, then the colo pseudo-nodes `Graph` adds (`kind: "colo"`, `id` `colo:<edge>:<code>`), at most 256 and 32 of them.
  - `name`, `kind`, `group`, `provider` and `parent` come from the node.
  - `place` is its location's label: its parent's when `inherited`, the colo's city for a colo, `""` when it has none.
  - `lat` and `lon` are degrees when `located`, and `null` otherwise. `located` is `true` when the node has a declared location, its own or, when `inherited`, its parent's.
  - `health` and `affected` are the node's state as the TUI shows it. In a cached view, every `health` is `unknown`.
  - `signal` is what the node may claim, `view.NodeSignal`: `up`, `affected`, `degraded`, `down` or `unknown`, and for a colo `carried` too. Consumers draw `signal`; they never derive it from `health` and `affected`.
- **`edges`:** at most 512, in `Graph`'s order: declared links, the hops in front of endpoints, the hops of declared paths, nodes hosted in others, then colo hops. Both ends of every edge are in `nodes`.
  - `kind` is `link`, `via`, `path`, `contains` or `colo` (`view.EdgeKinds`).
  - `signal` is what the edge may claim (`view.SignalRank`): `up`, `carried`, `affected`, `degraded`, `down` or `unknown`. A link no check measures is `carried` while a declared path over it succeeds end to end. A path hop is an expectation, never a measured link.
  - `observer` is, for a path hop, the observer whose declared path implies it, and `""` otherwise.
- **Too large to draw:** past either limit, `value: null`, `health: "unknown"`, `reason: "graph_too_large"`.
- **The row's `health`:** the worst node `health`. **`text`:** for example `"18 nodes in 7 places"`.
- **The row's `valid_until`:** the earliest deadline of the source envelope and of the node, link, path and check states the signals rely on, the checks that place colos included. The value has no nested deadlines: past the row's, the whole value is withheld (section 5).

## 4. When frames are written

These are the same rules as `topo monitor` output today, with the pipe as the sink:

- **Source refresh:** at most 5 s apart. Evidence ages every second.
- **Changed values:** written at the display cadence (`interval`).
- **Health, freshness and lifecycle transitions:** written at once.
- **Unchanged content:** skipped, except that the lease is renewed at least every 10 s.
- **The lease:** `publisher_expires_at` is the frame's time plus 30 s.
- **No buffering:** each frame is one write followed by a flush.

## 5. Reader rules (consumers)

These are the rules `topo monitor preview` applies, and topophany-bar's `ReaderPolicy` implements them:

- **Every second, check deadlines** against the consumer's clock. When `publisher_expires_at` has passed, everything is unavailable and the status item shows ◌. When a row's `valid_until` has passed, that row's value is withheld.
- **For `server.card`, also apply each resource and nested observer deadline,** and **for `service.card`, each check's deadline,** as specified in section 3.3, even when the row itself remains current. A renewed publisher lease never renews these nested deadlines.
- **Treat implausibly future timestamps as unavailable.** A timestamp is implausible when it lies more than 5 minutes beyond the consumer's clock.
- **Never extend a row's validity** because a later frame renewed the lease without changing that row.
- **Treat the process exiting, or stdout closing, as unavailable at once.**
- **Never show an error frame as content.** Keep the last `running` frame and apply the rules above to it.

## 6. Versioning

Fields may be added to requests, frames and values without changing `protocol`, and consumers ignore fields they don't know. Renaming or removing a field, or changing a meaning, needs protocol 2, and `--capabilities` must then list both protocols for as long as both are served.

## 7. Direct v1 (D1)

The additive schema/protocol 1 extension is specified in the verified
[`contracts/direct-v1/contract.md`](contracts/direct-v1/contract.md). Its manifest
and fixtures are copied byte-for-byte from topophany; tests validate their hashes.
`client`, `preview` and `direct` are exclusive source modes. Unknown modes are
retained in Settings and rejected by capability negotiation rather than becoming
client connections. `--profiles` retains its client meaning; direct profiles come
from `topo sources list --json`.

A direct request explicitly names a profile, optionally fences installation with
`profile_revision`, and projects `sources.status`, `servers.list`, and deduplicated
`server.card` rows. Template/source/metric support are checked separately from
protocol support. Row admission is bounded at 128 with an explicit error. Collector
section preferences survive mode switches; the collector view is scoped to its
mode as profiles are, so direct requests and Terminal arguments carry no observer
and switching back restores the view that mode was left in. No resource
thresholds or network health aggregation are implemented by the bar.

The one-shot `sources inspect/save/remove --json-stdin` executor sends authentication
only on stdin, bounds input/output to 256 KiB / 1 MiB, drains stderr concurrently
without displaying its body, and validates schema, request ID, envelope and exit
status. Its default deadline is 45 seconds. Password/token values live only in an
editing session. Inspect does not carry an implicit token into save. A conflict or
unknown save outcome reads the profile again and requires review before retrying.
Closing the editor cancels its process and clears its secret fields.

Capabilities' `direct.adapters` names what `topo` reads. The bar sets up `beszel`
and `komari`, in that order, offers only those `topo` lists, and treats direct as
unsupported when it lists neither. Authentication follows the adapter: Beszel takes
`password` or `token`, Komari a raw administrator API key as `token` or `anonymous`
for public nodes; either takes `saved` for an existing source, which keeps its
adapter. The bar never sends `env`. Object IDs are opaque: 15 characters for
Beszel, a lowercase UUID for Komari. A new Komari source asks for a 30-second
interval, as topo's guide suggests for Komari's one-minute recent window.

A source ID is generated once per editor, `bs-` and UUID hex as the contract says,
whatever its adapter. Returned node IDs are used unchanged;
`origin` stays distinct from provider. Optional malformed origin fields are ignored
locally. `profile_revision`, request ID, config revision and dataset ID retain their
separate meanings. A running frame confirms installation; a matching error rejects
only its request. Old process and request generations cannot install new content.
The reader clears evidence/history when source + dataset changes. Pins are scoped
by mode and stable profile; direct Widget node choices also include dataset identity.

The stream continues across profile/pin/template/language/display updates. Explicit
retry and Mac wake use a debounced `retry_nonce`, only when advertised. Direct-root,
command-response, engine and clock injection are development dependencies, absent
from normal Settings. Terminal arguments use `--source direct --profile ID` with
no Hub URL, authentication or observer. App exit closes its stream and cancels
config commands.

The old statement that stream never writes files applies to client/preview. D1 may
lock/read/atomically renew its credentials in its private root. It writes no metrics
journal, panel file or history database.

Direct Widget handoffs contain only public Settings and display frames. Each
Widget's expiry uses the earliest relevant original row/resource deadline, with
no heartbeat grace. Snapshot publication, sample time, source contact and handoff
write time remain distinct. Direct snapshot writes may happen every 15 seconds;
resource-only reload requests are limited to once per minute. WidgetKit controls
execution. Collector Widget schedules retain their existing heartbeat policy.

## 8. Local checks (this Mac)

`topo` can read this Mac's own runtime checks with no collector: for now the
mihomo proxy engine's status API (its "external controller") on literal loopback
(`127.0.0.0/8`, `::1` or `localhost`). Unlike `direct`, `local` is not a mode the
panel reads *instead of* another: the bar runs it as a second
`topo monitor stream` beside the panel's own source, whatever that is.

Capabilities list `local` in `sources` and add
`"local": {"schema": 1, "config_api": 1, "adapters": ["mihomo"], "limits": {"checks": 4}}`;
`check.card` and `checks.list` list `local` among their sources. The bar sets up
mihomo only when `local.adapters` contains it, and starts the local stream only
with the `topo` the panel already runs, never in a demo, preview or fixture.

`topo local list --json` and `topo local inspect|save|remove --json-stdin` use
the `topo sources` envelope, bounds and exit codes (2 for a request that fails
validation). A check is `{id, name, adapter: "mihomo", url, interval_seconds,
timeout_seconds, stale_seconds, root_proxy, expected_mode, expected_tun}`; the
bar generates `lc-` and 16 hex digits as its ID, sends `expected_tun` as an
explicit `null` for no expectation, and checks the address is local before
asking. The secret travels only in one command's stdin as
`{"mode":"token","token":…}` (trimmed of the whitespace a paste brings),
`{"mode":"none"}` or `{"mode":"saved"}`; `topo` keeps it in its own 0600 file
and never prints it. The bar never stores it: the editor clears it on save or
close. Inspect returns the engine's version, mode and TUN and its proxy groups,
to choose the one to follow; save reads the engine again with the same secret
before writing and fences on `base_revision`. A conflict or unknown outcome
lists again and asks for review before retrying.

The stream request is `source: "local"` with no profile, project, observer,
credentials, scenario, `lang` or `retry_nonce`, the store's `profile_revision`,
and one `check.card` row per check (`local-1`…), all with history: there are at
most four, read on this Mac. A new request line after a save or removal makes
the same process reload; `profile_conflict` makes the bar list again. Frames
carry `source` and `project` `local`; card observers are `This machine`, which
the bar names This Mac. `latency` and `up_24h` are null. Health, policy and
wording are a worker's mihomo check's: an engine that doesn't answer is a
`fail` (`network_error` or `timeout` at `adapter_api`), degraded on the first
read and down on the second; a rejected secret is a monitor `error`.

The local reader has its own lifetime: it lists and streams only while a check
is set up and the running `topo` reads them, restarts with the panel's `topo`
path, ignores frames of an earlier request, and closes its stdin at quit.
Expanding a local card changes no request. Its cards come first in Pinned,
including while the panel reads Beszel or Komari directly.

## Collector diagnostics and monitoring cards

Protocol 1 additionally negotiates `collector_read`, `client_retry` and
`card_history` booleans. Missing capabilities are false. New metrics are optional:
`checks.list`, `check.card` (`select.check`), `links.list`, `link.card`
(`select.link`). Unsupported options are removed before sending a request.

`collector_read` is the last snapshot acquisition, independent of business
health and evidence freshness. Its completed/success timestamps do not advance
on a heartbeat or retry acknowledgment. Only an actual completed acquisition
advances them. Expired publisher diagnostics are history.

Checks share the service card's check fields and optional `diagnostic` containing
outcome, evidence/path evidence, stage/code, policy confirmation, allowlisted
facts and declared expectations. Link cards contain the collector's link summary
and check cards. Each nested check loses health, readings and diagnostics at its
own deadline; that does not expire the enclosing link. Check/link history and
names use distinct selector identities. Project and observer changes clear prior
history. The app never derives health from diagnostic facts.

Pinned monitoring selections are stored alongside service choices as
`monitors: [{"kind":"check","id":"m-clash"},{"kind":"link","id":"home-cf"}]`.
The section keeps its existing `services` identity. At most 16 monitoring pins
are requested, with separate check/link focus identities and profile-scoped
preferences. Direct mode requests neither metric. The chooser only offers
supported categories. Missing rows are described as absent from this view,
without asserting that a check absent from an observer view was deleted.

An adapter check's diagnostic may carry `policy`: `not_configured`, `unverified`,
`matched` or `violated`, `topo`'s judgment of its declared policy (the TUI's
"Policy check"). Expanded cards show it as a Policy field; absent, none is shown.
A mihomo runtime read is said to match its policy only when one is declared:
`policy` other than `not_configured`, or, from a `topo` without the field, an
expectation or a provider comparison. Otherwise it says no policy is declared.

When an HTTP check's facts say the edge answered in the application's place
(`edge_mitigation: "challenge"`, then `edge_access: "login_redirect"`), an `ok`
or `fail` card says so instead of passing or failing: the origin was not asked,
as Topophany's engine words it. A service card with no failing, policy or error
check says the same instead of "all passing". Health and pills remain `topo`'s.

Codes are named, not interpreted: 1.5.2's probe policies (`certificate_expiring`,
`latency_exceeded`, `json_assertion_mismatch`), edge, trace, exit and WireGuard
policies, failed response assertions, and the monitor's own read errors
(credentials, provider references, response budgets, unavailable APIs or
metrics). A monitor error stays the monitor's, never the service's. Unknown codes
fall back to the outcome's words, and the expanded card keeps the stage and code.

A probe policy says how far off it is when `topo` reports the measurement:
`facts.tls_days_remaining` makes `certificate_expiring` "Certificate expires in
9 days" (today, tomorrow), and `expected.max_duration_ms` makes
`latency_exceeded` "Slower than its 800 ms budget", with the reading starting
"took 1.43 s" from the diagnostic's `duration_ms`. Expanded, the card adds the
certificate's `tls_not_after` date (in the Mac's time zone), the `tls_min_days`
warning window, the budget and the last request's duration. Without these fields
the code alone is named as before.

Tailscale and WireGuard checks read this observer's own runtime, in the closed
shapes `topo` exports (any other value under those keys is withheld upstream).
A Tailscale card names the backend state, whether the peer is reported online
and active (idle is not offline), when it was last seen if reported, the path
`transport_hint` suggests, and an optional ping's protocol, latency and route.
Its reading is the ping or the hinted path, then "last seen" for an offline
peer or "idle". A WireGuard card reads the last handshake's age (or none yet),
received and sent bytes from two non-atomic reads, and its AllowedIPs and
keepalive against the declared policy; an old handshake is not judged a
failure. Both kinds' passing summaries say the service or tunnel is unproven,
and their backend, peer and command codes are named.

A mihomo card's expanded rows read its facts in plain words: mode and TUN against
their expectations, the core's last delay with the age `core_last_checked` gives
it, the reference's publication age, and one row per provider in
`provider_comparison` (`name=status`, optionally followed by counts in
parentheses). A match says so. A mismatch names missing and extra counts, a
changed order, or that the provider isn't loaded, then the loaded members from
`provider.<name>`. Settling says how many are loaded and when the core last
loaded it. Closed words from credential-bearing controllers say only whether
it differs. A partial entry cut at the fact budget is dropped.

Cloudflare cards read every allowlisted fact. cloudflared shows HA connections,
edge locations against expected colos, requests and errors, active streams and
version. API tunnels show the API's status word (also the reading when it sends
no connections list), reconnecting connections, connector versions and the
oldest connection's age. DNS shows proxied against its expectation, content
comparison and TTL. Pools show pool and per-origin health and regions reporting.
HTTP checks append Cloudflare's `edge_rtt_ms` ("<1 ms" for zero). Trace checks
read colo, WARP and Gateway as reported, with HTTP and TLS as fields. A check
naming `edge_provider`, or carrying trace facts, takes that provider's mark.

A service card lists what its checks say beyond their marks, by observer:
failures, then monitor errors, then policies and edge stand-ins, each distinct
diagnosis once and three at most in the panel, then how many more Topophany
shows. Widgets keep the first in their one line. Diagnoses go with each check's
diagnostic at its own deadline, and with the card at its row's.

Panel service cards also show the topology's `memo`, the edge's 24 h
`answered_from` colos and cache statuses, and the worst current check's
`first_byte` line as `topo` writes it. Native's p50 carries the check's p95 as a
tooltip and to VoiceOver. A withheld card keeps its memo and drops the rest.
Widgets keep their layout.

A service card's `runbook` opens from the panel only when it is an absolute
http(s) URL with a host: a Runbook button in Native's foot, and a last
"↗ runbook host" line in Terminal with a button laid over its region. That
region is cached with the section's raster like the monitoring regions. Other
schemes stay unopened.

A Check widget shows one check's or link's card. The extension records its pin
in `widget-needs.json`, and the app adds `check.card` or `link.card` for pins the
panel doesn't request (`widget-monitor-N`), always with `history: true`. A
pinned row gains history while a widget draws it. Direct mode requests neither.
The widget card follows the pinned card's deadlines, and its mark joins the
reload signature.

`service.card.assessment`, from a `topo` that sends it, is the Services tab's
assessment: `state` (`up`, `health_warn`, `local_fail`, `path_warn`,
`access_fail` or `unknown`), `availability`, `path_reachability`,
`worker_online`, up to 16 scoped `evidence` entries, closed `hints` codes and its
own `valid_until`. Panel service cards state a failing or warning local health
check, or a path failure that is not by itself an outage, with "app · path ·
workers" beneath. `single_remote_check` suggests adding a local health check;
unknown hint codes are never shown. At the assessment's deadline, or one more
than five minutes ahead, every word becomes unknown and the conclusion goes.
The bar never derives the state.

The panel presents one conclusion and one selected reading per monitoring card.
Expanded evidence reuses the service card's typography, marks and history strip.
Reported runtime paths and core historical delays remain labeled as such; report
acquisition latency is labeled “Read p50”. Adapter facts never decide health in
bar. Unknown and expired evidence retains names but loses readings and diagnoses.

Monitoring cards start with `history: false`. When `card_history` is supported,
first disclosure requests history for that pin. The demand set is bounded by
current pins and retained across collapse/reopening, so those gestures do not
repeatedly replace the source or its history book. Unpinning and profile changes
release the demand. Existing service cards and Service widgets retain their
history. A history-only template update does not display a configuration notice.

A live `collector_read.state == "waiting"` is awaiting the first acquisition,
not a failed connection. It uses neutral waiting text and connecting activity.
A stopped stream ends an in-progress refresh indication immediately; an
outstanding retry identity remains recognizable if the supervisor restarts with
that request. Historical row values are bounded to the active template's keys.

### Availability coverage

`summary.verdict.coverage` optionally contains `observer`, `services` and
`known`. Counts describe service availability established by evidence in the
selected view, independently of the check verdict. Known includes healthy,
degraded and failed availability. Invalid counts are withheld; older frames
omit the caption. The caption disappears when the verdict is cached or expired.
It uses Topophany 1.5.2's wording ("Service availability: 3/23 known") and, in
Terminal, the TUI's place under the count. A `topo` after 1.5.2 adds
`coverage.reasons`, closed codes counted ("5 no app check · 3 awaiting
samples"). They're accepted only when they sum to the unknown services. Native's
tooltip and a second Terminal line name them, most first. Without them, Native's
tooltip points to Topophany's Services tab. `services.list` entries and
`service.card` may carry `unknown_reason` with the same codes. A service card
then says "App availability unknown: …", leaving the app out of the assessment's
readings. Unmonitored and not-seen-from-here cards say why already.
It updates with the status model, adding no timer or background task; only the
status drawing region gains a line and existing layout measures its size.

`investigation: true` advertises the CLI's `doctor`, `compare` and
`--related-incidents` entry points. Missing/invalid values are false. The menu
bar offers corresponding terminal shortcuts only when this flag is present.
Direct mode omits incident/history shortcuts; synthetic preview omits live
connection diagnosis. History comparison retains the selected profile but
intentionally compares all observers for the chosen service.
