// Sample frames for the preview: what `topo monitor stream` would send, already
// decoded into what the panel draws. The network is `topo preview`'s homelab.
(function () {
  // A smooth, repeatable series for sparklines.
  function series(seed, n, base, swing, floor, ceil) {
    const out = [];
    let v = base;
    for (let i = 0; i < n; i++) {
      const s = Math.sin(seed * 12.9898 + i * 78.233) * 43758.5453;
      const r = s - Math.floor(s) - 0.5;
      v = v + r * swing + (base - v) * 0.18;
      out.push(Math.max(floor, Math.min(ceil, v)));
    }
    return out;
  }

  const OBSERVERS = [
    'Seattle MacBook', 'Seattle Windows', 'Home Router', 'San Jose', 'New York Oracle',
    'New York Azure', 'LA BandwagonHost', 'LA Oracle', 'Frankfurt', 'Tokyo', 'Honolulu',
  ];

  const APPS = (over) => [
    { name: 'Proxy chain', services: ['up', 'up', 'up', 'up', 'up', 'up'] },
    { name: 'Code & backups', services: ['up', 'up', 'unknown'], note: '1 not monitored', tuiNote: '1 not monitored', quiet: true, health: 'unknown' },
    { name: 'Main site', services: ['up', 'up', 'up'] },
    { name: 'Personal cloud', services: ['up', 'up', 'up', 'up', 'up'] },
    { name: 'Remote access', services: ['up', 'up'] },
    { name: 'Serverless', services: ['up', 'up', 'up', 'up'] },
  ].map((a) => Object.assign(a, (over || {})[a.name] || {}));

  const SERVERS = (over) => [
    {
      name: 'Oracle New York', kind: 'host', provider: 'Oracle', place: 'New York', health: 'up',
      cpu: { v: 26.3, limit: 90, detail: '8 CPUs' },
      mem: { v: 46.2, limit: 90, detail: '7.4 / 16 GiB' },
      disk: { v: 58.4, limit: 90, detail: '150 / 256 GiB' },
      services: '4 services · 3 up · 1 not monitored', updated: '4s ago',
      svc: [{ name: 'Main Site (Caddy + Blog)', health: 'up' }, { name: 'Main Site API', health: 'up' }, { name: 'Memos', health: 'up' }, { name: 'Nightly Backup', health: 'unknown', note: 'not monitored' }],
      observes: { name: 'New York Oracle Cloud', health: 'up', text: '9 checks · all pass', ago: '4s ago' },
    },
    {
      name: 'BandwagonHost LA', kind: 'host', provider: 'BandwagonHost', place: 'Los Angeles', health: 'up',
      cpu: { v: 41.0, limit: 90, detail: '4 CPUs' },
      mem: { v: 63.5, limit: 85, detail: '2.5 / 4 GiB' },
      disk: { v: 84.2, limit: 90, detail: '33.7 / 40 GiB' },
      services: '6 services · all up', updated: '5s ago',
      svc: [{ name: 'VLESS+Reality Entry', health: 'up' }, { name: 'Exit Candidate A', health: 'up' }, { name: 'Exit Candidate B', health: 'up' }, { name: 'Relay contrast', health: 'up' }],
    },
  ].map((s) => Object.assign(s, (over || {})[s.name] || {}));

  const LOCAL = {
    model: 'MacBook Pro', chip: 'M4 Pro',
    cpu: { v: 16.8, sys: 5.2, user: 11.6, spark: series(3, 40, 17, 9, 4, 60) },
    mem: { v: 72.4, pressure: 40.2, app: 5.5, wired: 3.5, comp: 3.4, total: 24 },
    disk: { v: 43.7, used: 107.1, total: 245.1 },
    net: {
      iface: 'Wi-Fi', ip: '192.168.31.116', up: '329.5 kB/s', down: '343.9 kB/s',
      upSpark: series(7, 40, 30, 22, 2, 90), downSpark: series(11, 40, 45, 26, 4, 95),
    },
    battery: { v: 82, state: 'Charging', remain: '1:12 to full' },
  };

  const MAC_SERVER = (over) => Object.assign({
    name: 'MacBook Pro', kind: 'laptop', provider: 'Home', place: 'Seattle', health: 'up',
    cpu: { v: 18.2, limit: 95, detail: '14 CPUs' },
    mem: { v: 68.0, limit: 95, detail: '16.3 / 24 GiB' },
    disk: { v: 43.7, limit: 90, detail: '107 / 245 GiB' },
    services: '2 services · all up', updated: '5s ago',
    svc: [{ name: 'Tailscale', health: 'up' }, { name: 'Topophany worker', health: 'up' }],
    observes: { name: 'Seattle MacBook', health: 'up', text: '14 checks · all pass', ago: '5s ago' },
  }, over || {});

  const seen = (bad) => OBSERVERS.map((name) => Object.assign({ name, health: 'up' }, bad[name] || {}));

  // Every node with a card in the Servers tab (servers.list): its kind, its
  // provider and the place it names. Time zones groups them by the zone each
  // place suggests; Fleet by provider, edges and platforms first.
  const LISTED = [
    ['macbook', 'MacBook Pro', 'laptop', 'Home', 'Seattle'], ['seattle-pc', 'Windows Desktop', 'desktop', 'Home', 'Seattle'],
    ['router', 'Home Router', 'router', 'Home', 'Seattle'], ['sj-vultr', 'Vultr San Jose', 'host', 'Vultr', 'San Jose'],
    ['bwh-la', 'BandwagonHost LA', 'host', 'BandwagonHost', 'Los Angeles'], ['oracle-la', 'Oracle LA', 'host', 'Oracle', 'Los Angeles'],
    ['hnl-vultr', 'Vultr Honolulu', 'host', 'Vultr', 'Honolulu'], ['oracle-ny', 'Oracle New York', 'host', 'Oracle', 'New York'],
    ['azure-ny', 'Azure New York', 'host', 'Azure', 'New York'], ['fra-hetzner', 'Hetzner Frankfurt', 'host', 'Hetzner', 'Frankfurt'],
    ['tokyo-vps', 'GCP Tokyo', 'host', 'GCP', 'Tokyo'], ['cloudflare', 'Cloudflare', 'edge', 'Cloudflare', 'anycast'],
    ['vercel', 'Vercel', 'edge', 'Vercel', 'anycast'], ['supabase', 'Supabase', 'platform', 'Supabase', 'Tokyo'],
  ];
  const listed = (over) => LISTED.map(([id, name, kind, provider, place]) => ({ id, name, kind, provider, place, health: (over || {})[id] || 'up' }));
  // The zone each place's name suggests; Settings can change any of them.
  const PLACE_ZONES = {
    Seattle: 'America/Los_Angeles', 'San Jose': 'America/Los_Angeles', 'Los Angeles': 'America/Los_Angeles',
    Honolulu: 'Pacific/Honolulu', 'New York': 'America/New_York', Frankfurt: 'Europe/Berlin', Tokyo: 'Asia/Tokyo',
  };

  const S = {};

  S.clear = {
    key: 'clear', label: 'All clear',
    verdict: { state: 'clear', health: 'up', title: 'All clear', tui: 'ALL CLEAR', count: 0,
      sub: '68 of 68 checks passing', bigTop: 'checks passing', bigBottom: 'of 68 configured', big: '68' },
    counts: { up: 68, warn: 0, down: 0, unknown: 0 }, configured: 68, incidents: 0,
    observers: { live: 11, total: 11 }, updated: '3s ago', collector: 'tokyo', live: true,
    seen: seen({}),
    attention: [], more: 0,
    apps: APPS(),
    servers: SERVERS(),
    mac: MAC_SERVER(),
    listed: listed(),
  };

  S.degraded = {
    key: 'degraded', label: 'Degraded',
    verdict: { state: 'degraded', health: 'degraded', title: 'Degraded', tui: 'DEGRADED', count: 2,
      sub: '2 checks warning · no incidents', bigTop: 'checks warning', bigBottom: 'of 68 configured', big: '2' },
    counts: { up: 66, warn: 2, down: 0, unknown: 0 }, configured: 68, incidents: 0,
    observers: { live: 11, total: 11 }, updated: '2s ago', collector: 'tokyo', live: true,
    seen: seen({ 'Seattle MacBook': { health: 'degraded', note: '1 warn' }, 'Seattle Windows': { health: 'degraded', note: '1 warn' } }),
    attention: [
      { health: 'degraded', title: 'VLESS+Reality Entry (Primary)', kind: 'service', state: 'WARN', from: 'Seattle MacBook', since: null, why: 'egress IP outside expected range' },
      { health: 'degraded', title: 'Exit Candidates (BandwagonHost · Azure)', kind: 'path', state: 'WARN', from: 'Seattle Windows', since: null, why: 'provider order differs' },
    ], more: 0,
    apps: APPS({ 'Proxy chain': { services: ['degraded', 'degraded', 'up', 'up', 'up', 'up'], note: '2 attention', tuiNote: '2 attention', health: 'degraded' } }),
    servers: SERVERS(),
    mac: MAC_SERVER({ observes: { name: 'Seattle MacBook', health: 'degraded', text: '14 checks · 1 warn', ago: '5s ago' } }),
    listed: listed(),
  };

  S.incidents = {
    key: 'incidents', label: 'Incidents',
    verdict: { state: 'incidents', health: 'down', title: '5 incidents', tui: '5 INCIDENTS', count: 5,
      sub: '5 checks down · 63 of 68 passing', bigTop: 'checks failing', bigBottom: 'of 68 configured', big: '5' },
    counts: { up: 63, warn: 0, down: 5, unknown: 0 }, configured: 68, incidents: 5,
    observers: { live: 11, total: 11 }, updated: '4s ago', collector: 'tokyo', live: true,
    seen: seen({
      'Seattle Windows': { health: 'down', note: '3 down' },
      'Seattle MacBook': { health: 'down', note: '1 down' },
      'San Jose': { health: 'down', note: '1 down' },
    }),
    attention: [
      { health: 'down', title: 'Primary BandwagonHost → Oracle Exit A', route: true, kind: 'incident', state: 'OPEN', from: 'Seattle MacBook', since: '4m', why: 'connect timed out at hop 2' },
      { health: 'down', title: 'Relay contrast → BandwagonHost LA', route: true, kind: 'incident', state: 'OPEN', from: 'San Jose', since: '4m', why: 'connection refused' },
      { health: 'down', title: 'Direct entry to BandwagonHost', route: true, kind: 'incident', state: 'OPEN', from: 'Seattle Windows', since: '4m', why: 'TCP reset after TLS hello' },
      { health: 'down', title: 'Primary BandwagonHost → Oracle Exit A', route: true, kind: 'incident', state: 'OPEN', from: 'Seattle Windows', since: '3m', why: 'connect timed out at hop 2' },
      { health: 'down', title: 'Primary BandwagonHost → Vultr Exit B', route: true, kind: 'incident', state: 'OPEN', from: 'Seattle Windows', since: '3m', why: 'connect timed out at hop 2' },
    ], more: 12,
    apps: APPS({ 'Proxy chain': { services: ['degraded', 'degraded', 'up', 'degraded', 'up', 'up'], note: '3 attention', tuiNote: '3 attention', health: 'degraded' } }),
    servers: SERVERS({ 'BandwagonHost LA': { health: 'degraded', pill: 'AFFECTED',
      svc: [{ name: 'VLESS+Reality Entry', health: 'degraded', note: 'affected' }, { name: 'Exit Candidate A', health: 'degraded', note: 'affected' }, { name: 'Exit Candidate B', health: 'up' }, { name: 'Relay contrast', health: 'degraded', note: 'affected' }] } }),
    mac: MAC_SERVER({ observes: { name: 'Seattle MacBook', health: 'down', text: '14 checks · 1 down', ago: '5s ago' } }),
    listed: listed({ 'bwh-la': 'degraded' }),
  };

  S.incomplete = {
    key: 'incomplete', label: 'Incomplete',
    verdict: { state: 'incomplete', health: 'unknown', title: 'Evidence incomplete', tui: 'INCOMPLETE EVIDENCE', count: 7,
      sub: '7 checks without current evidence', bigTop: 'checks unknown', bigBottom: 'of 68 configured', big: '7' },
    counts: { up: 61, warn: 0, down: 0, unknown: 7 }, configured: 68, incidents: 0,
    observers: { live: 10, total: 11 }, updated: '3s ago', collector: 'tokyo', live: true,
    seen: seen({ Honolulu: { health: 'unknown', note: 'silent 3m' } }),
    attention: [
      { health: 'unknown', title: 'Honolulu Vultr', kind: 'observer', state: 'UNKNOWN', from: 'Honolulu', since: null, why: 'last heard 3 min ago · 7 checks unknown' },
      { health: 'unknown', title: 'Transit → Internet', route: true, kind: 'path', state: 'UNKNOWN', from: 'Honolulu', since: null, why: 'no current evidence' },
    ], more: 0,
    apps: APPS({ 'Proxy chain': { services: ['up', 'up', 'up', 'up', 'unknown', 'unknown'], note: '2 unknown', tuiNote: '2 unknown', health: 'unknown' } }),
    servers: SERVERS(),
    mac: MAC_SERVER(),
    listed: listed(),
  };

  S.offline = {
    key: 'offline', label: 'Offline',
    verdict: { state: 'offline', health: 'cached', title: 'Offline', tui: 'OFFLINE', count: 0,
      sub: 'Collector unreachable · retrying every 5 s', bigTop: 'collector unreachable', bigBottom: 'last snapshot 3 min ago', big: '--' },
    counts: { up: 0, warn: 0, down: 0, unknown: 68 }, configured: 68, incidents: 0,
    observers: { live: 0, total: 11 }, updated: '3 min ago', collector: 'tokyo', live: false,
    lastKnown: 'All clear',
    seen: seen({}).map((o) => Object.assign(o, { health: 'unknown' })),
    attention: [], more: 0,
    apps: APPS().map((a) => Object.assign(a, { services: a.services.map(() => 'unknown'), note: 'cached', tuiNote: 'cached', cached: true })),
    servers: SERVERS().map((s) => Object.assign(s, { withheld: true, health: 'unknown', updated: '3 min ago' })),
    mac: MAC_SERVER({ withheld: true, health: 'unknown', updated: '3 min ago',
      observes: { name: 'Seattle MacBook', health: 'unknown', text: 'not known while offline', ago: '3 min ago' } }),
    listed: listed().map((x) => Object.assign(x, { health: 'cached' })),
  };

  // No topo on this Mac, or one too old: nothing was ever received, and the
  // Status card offers to download it.
  S.missing = Object.assign({}, S.offline, {
    key: 'missing', label: 'No topo', missing: true, lastKnown: null, updated: '',
    verdict: { state: 'offline', health: 'cached', title: 'Offline', tui: 'OFFLINE', count: 0,
      sub: 'topo not found · download it, or choose one in Settings', bigTop: 'topo not running', bigBottom: 'nothing current is known', big: '--' },
  });

  const SHORT = { missing: 'Nothing current is known', clear: '68 of 68 checks pass', degraded: '2 warn · 66 of 68 up', incidents: '5 down · 63 of 68 up', incomplete: '7 unknown · 61 of 68 up', offline: 'Last known: all clear' };
  Object.values(S).forEach((sc) => { sc.short = SHORT[sc.key]; sc.age = sc.live ? '1 min ago' : '3 min ago'; });

  // What a widget shows once its deadline passes and the app hasn't renewed
  // it: the last verdict it knew, as history rather than as now.
  S.stale = Object.assign({}, S.incidents, {
    key: 'stale', label: 'Not current', live: false, age: '47 min ago', lastKnown: '5 incidents',
    verdict: { state: 'offline', health: 'cached', title: 'Not current', tui: 'NOT CURRENT', count: 0,
      sub: 'topophany-bar stopped · 47 min ago', bigTop: 'not current', bigBottom: 'last known 47 min ago', big: '--' },
    short: 'Last known: 5 incidents', counts: { up: 0, warn: 0, down: 0, unknown: 68 }, incidents: 0, observers: { live: 0, total: 11 },
    attention: [], more: 0, seen: S.offline.seen, apps: S.offline.apps, servers: S.offline.servers, mac: S.offline.mac,
    listed: S.offline.listed,
  });

  // The fixtures' moment, and This Mac's zone: Seattle, at 6:30 AM.
  window.TB_DATA = { scenarios: S, order: ['clear', 'degraded', 'incidents', 'incomplete', 'offline'], local: LOCAL,
    now: Date.UTC(2026, 9, 18, 13, 30, 4), here: 'America/Los_Angeles', placeZones: PLACE_ZONES };
})();
