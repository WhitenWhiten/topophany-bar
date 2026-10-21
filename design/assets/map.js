// Topophany Bar design preview: the map (DESIGN.md §4.3). The same
// framing, sites, arcs and dither the app's map draws (Sources/
// TopophanyThemes/Map, Cards/CardsMapPainter, Cells/CellsMap), from the
// fixtures' map.graph (scripts/make-fixtures.py). Each map is a <canvas
// data-map="…">, drawn once it's in the page.
(function () {
  const TB = window.TB;
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

  // ---------------------------------------------------------------- land
  const LAND = (() => {
    const b = atob(window.TB_LAND || '');
    const a = new Uint8Array(b.length);
    for (let i = 0; i < b.length; i++) a[i] = b.charCodeAt(i);
    return a;
  })();
  function isLand(lat, lon) {
    let l = (lon + 180) % 360;
    if (l < 0) l += 360;
    const col = Math.min(719, Math.floor(l * 2)), row = Math.min(359, Math.max(0, Math.floor((90 - lat) * 2)));
    const i = row * 720 + col;
    return (i >> 3) < LAND.length && (LAND[i >> 3] & (0x80 >> (i & 7))) !== 0;
  }

  // ---------------------------------------------------------------- data
  // The fixtures' graph: id, name, kind, place, lat, lon, parent.
  const NODES = [
    ['seattle-pc', 'Windows Desktop', 'desktop', 'Seattle', 47.61, -122.33], ['macbook', 'MacBook Pro', 'laptop', 'Seattle', 47.61, -122.33],
    ['router', 'Home Router', 'router', 'Seattle', 47.61, -122.33], ['sj-vultr', 'Vultr San Jose', 'host', 'San Jose', 37.34, -121.89],
    ['bwh-la', 'BandwagonHost LA', 'host', 'Los Angeles', 34.05, -118.24], ['oracle-la', 'Oracle LA', 'host', 'Los Angeles', 33.99, -118.31],
    ['hnl-vultr', 'Vultr Honolulu', 'host', 'Honolulu', 21.31, -157.86], ['oracle-ny', 'Oracle New York', 'host', 'New York', 40.71, -74.01],
    ['postgres-box', 'PostgreSQL Container', 'container', 'New York', 40.71, -74.01, 'oracle-ny'],
    ['azure-ny', 'Azure New York', 'host', 'New York', 40.73, -73.94], ['tokyo-vps', 'GCP Tokyo', 'host', 'Tokyo', 35.68, 139.77],
    ['openlist', 'OpenList', 'container', 'Tokyo', 35.68, 139.77, 'tokyo-vps'], ['fra-hetzner', 'Hetzner Frankfurt', 'host', 'Frankfurt', 50.11, 8.68],
    ['cloudflare', 'Cloudflare', 'edge', '', null, null], ['vercel', 'Vercel', 'edge', '', null, null],
    ['supabase', 'Supabase', 'platform', 'Tokyo', 35.68, 139.77], ['internet', 'Internet', 'external', '', null, null],
    ['visitors', 'Visitors', 'external', '', null, null],
    ['colo:SJC', 'SJC', 'colo', 'San Jose', 37.36, -121.93], ['colo:FRA', 'FRA', 'colo', 'Frankfurt', 50.03, 8.56],
  ];
  const LINKS = [
    ['win-transit', 'seattle-pc', 'bwh-la', 'up'], ['mac-transit', 'macbook', 'bwh-la', 'up'], ['win-aux', 'seattle-pc', 'azure-ny', 'up'],
    ['mac-aux', 'macbook', 'azure-ny', 'up'], ['transit-exit-a', 'bwh-la', 'oracle-la', 'up'], ['transit-exit-b', 'bwh-la', 'hnl-vultr', 'up'],
    ['aux-exit-a', 'azure-ny', 'oracle-la', 'up'], ['aux-exit-b', 'azure-ny', 'hnl-vultr', 'up'], ['exit-a-net', 'oracle-la', 'internet', 'carried'],
    ['exit-b-net', 'hnl-vultr', 'internet', 'carried'], ['win-router', 'seattle-pc', 'router', 'up'], ['mac-router', 'macbook', 'router', 'up'],
    ['relay-win', 'sj-vultr', 'seattle-pc', 'up'], ['visitors-relay', 'visitors', 'sj-vultr', 'carried'], ['visitors-cf', 'visitors', 'cloudflare', 'carried'],
    ['cf-app', 'cloudflare', 'oracle-ny', 'up'], ['visitors-jp', 'visitors', 'tokyo-vps', 'carried'], ['visitors-git', 'visitors', 'fra-hetzner', 'carried'],
    ['visitors-vercel', 'visitors', 'vercel', 'carried'], ['vercel-supabase', 'vercel', 'supabase', 'carried'], ['app-git', 'oracle-ny', 'fra-hetzner', 'up'],
    ['home-cf', 'seattle-pc', 'cloudflare', 'up'],
    ['colo-sjc', 'colo:SJC', 'cloudflare', 'carried', 'colo'], ['colo-fra', 'colo:FRA', 'cloudflare', 'carried', 'colo'],
    ['path:relay-entry', 'sj-vultr', 'bwh-la', 'carried', 'path'],
  ];
  const SCEN = {
    clear: { nodes: {}, edges: {} },
    degraded: { nodes: { 'bwh-la': 'affected' }, edges: { 'mac-transit': 'degraded', 'win-transit': 'affected', 'transit-exit-a': 'affected' } },
    incidents: { nodes: { 'bwh-la': 'degraded', 'oracle-la': 'affected', 'hnl-vultr': 'affected' },
      edges: { 'win-transit': 'down', 'mac-transit': 'down', 'transit-exit-a': 'affected', 'transit-exit-b': 'affected', 'exit-a-net': 'affected', 'exit-b-net': 'affected', 'path:relay-entry': 'down' } },
    incomplete: { nodes: { 'hnl-vultr': 'unknown' }, edges: { 'transit-exit-b': 'unknown', 'aux-exit-b': 'unknown', 'exit-b-net': 'unknown' } },
  };
  // Mark.troubleFirst: down, warn, unknown, not current, then up.
  const TROUBLE = { down: 0, degraded: 1, unknown: 2, cached: 3, up: 4 };
  const troubleFirst = (ns) => ns.map((n, i) => [n, i]).sort((a, b) => TROUBLE[a[0].mark] - TROUBLE[b[0].mark] || a[1] - b[1]).map((x) => x[0]);
  const RANK = { withheld: 0, unknown: 1, carried: 2, up: 3, affected: 4, degraded: 5, down: 6 };
  const MARK = { up: 'up', carried: 'up', affected: 'degraded', degraded: 'degraded', down: 'down', unknown: 'unknown' };

  /// The scenario's map, as SectionBuilder.map builds it: offline and not
  /// current keep the incidents' graph as history, every mark withheld.
  function graph(key) {
    const live = SCEN[key];
    const sc = live || SCEN.incidents;
    const nodes = NODES.map(([id, name, kind, place, lat, lon, parent]) => {
      const external = kind === 'external';
      const signal = sc.nodes[id] || (external ? 'unknown' : kind === 'colo' ? 'carried' : 'up');
      return { id, name, kind, place, parent: parent || '', at: lat == null ? null : { lat, lon }, colo: kind === 'colo',
        mark: live ? MARK[signal] : 'cached' };
    });
    const edges = LINKS.map(([id, from, to, line, kind]) => ({ id, from, to, kind: kind || 'link', line: live ? (sc.edges[id] || line) : 'withheld' }))
      .filter((e) => e.kind !== 'path' || (live && RANK[e.line] >= RANK.affected));
    return { nodes, edges, current: !!live };
  }
  TB.mapGraph = graph;
  const placesOf = (g) => [...new Set(g.nodes.filter((n) => n.at && !n.colo && n.place).map((n) => n.place))];

  // ------------------------------------------------------------- framing
  // GeoView.framing: equirectangular, cos(latitude) across, gaps over 60°
  // folded to 6° seams, as topo's geo map frames it.
  const FOLD_GAP = 60, FOLD_PAD = 15, FOLD_SEAM = 6;
  function lonBounds(lons) {
    const ls = lons.map((l) => ((l % 360) + 540) % 360 - 180).sort((a, b) => a - b);
    if (!ls.length) return [0, 0];
    let gap = 360 - (ls[ls.length - 1] - ls[0]), start = ls[0];
    for (let i = 1; i < ls.length; i++) if (ls[i] - ls[i - 1] > gap) { gap = ls[i] - ls[i - 1]; start = ls[i]; }
    const span = 360 - gap;
    return [start + span / 2, span];
  }
  function view(points, wd, height, ky, frame, folding = frame === 'fit') {
    const hd = height * ky;
    let lo = -56, hi = 80;
    for (const p of points) { lo = Math.min(lo, p.lat - 10); hi = Math.max(hi, p.lat + 10); }
    lo = Math.max(lo, -90); hi = Math.min(hi, 90);
    let cLat = (lo + hi) / 2, cLon = 10, spanLat = hi - lo, spanLon = 360;
    const folds = [];
    let removed = 0, lead = 0;
    if (points.length) {
      let span;
      [cLon, span] = lonBounds(points.map((p) => p.lon));
      const lats = points.map((p) => p.lat), minLat = Math.min(...lats), maxLat = Math.max(...lats);
      if (folding) {
        const west = cLon - span / 2;
        const ds = points.map((p) => (((p.lon - west + 1e-9) % 360) + 360) % 360).sort((a, b) => a - b);
        for (let i = 1; i < ds.length; i++) {
          const a = ds[i - 1] + FOLD_PAD, b = ds[i] - FOLD_PAD;
          if (ds[i] - ds[i - 1] > FOLD_GAP && b - a > 2 * FOLD_SEAM) { folds.push({ a, b, seam: FOLD_SEAM }); removed += b - a - FOLD_SEAM; }
        }
        span -= removed;
        cLon = west + span / 2;
      }
      if (frame === 'fit') {
        cLat = (minLat + maxLat) / 2;
        spanLon = Math.max(span + Math.max(32, span * 0.2), 64);
        spanLat = Math.max(maxLat - minLat + Math.max(22, (maxLat - minLat) * 0.35), 32);
      }
      lead = span / 2;
    }
    const kx = Math.min(1, Math.max(0.62, Math.cos((cLat * Math.PI) / 180)));
    const whole = Math.max((360 * kx) / wd, (hi - lo) / hd);
    const scale = Math.min(Math.max((spanLon * kx) / wd, spanLat / hd), whole);
    const vs = hd * scale;
    cLat = vs >= hi - lo ? (lo + hi) / 2 : Math.min(Math.max(cLat, lo + vs / 2), hi - vs / 2);
    const hs = (wd * scale) / kx;
    const g = { lon0: cLon - hs / 2, lat0: cLat + vs / 2, scale, kx, ky, x0: 0, x1: hs, lo, hi, folds: [] };
    if (folds.length) {
      if (hs >= 360 - removed) return view(points, wd, height, ky, frame, false);
      g.folds = folds.map((f) => ({ a: f.a + hs / 2 - lead, b: f.b + hs / 2 - lead, seam: f.seam }));
      g.x1 = unsqueeze(g, hs);
      return g;
    }
    if (hs > 360) { g.x0 = (hs - 360) / 2; g.x1 = (hs + 360) / 2; }
    return g;
  }
  function squeeze(g, d) {
    let out = d;
    for (const f of g.folds) {
      if (d >= f.b) out -= f.b - f.a - f.seam;
      else if (d > f.a) out -= (d - f.a) * (1 - f.seam / (f.b - f.a));
    }
    return out;
  }
  function unsqueeze(g, s) {
    let shift = 0;
    for (const f of g.folds) {
      const a = f.a - shift;
      if (s >= a + f.seam) shift += f.b - f.a - f.seam;
      else if (s > a) return f.a + ((s - a) * (f.b - f.a)) / f.seam;
      else return s + shift;
    }
    return s + shift;
  }
  function project(g, c) {
    let d = (c.lon - g.lon0 - g.x0) % 360;
    if (d < 0) d += 360;
    return { x: (squeeze(g, d + g.x0) * g.kx) / g.scale, y: (g.lat0 - c.lat) / g.scale / g.ky };
  }
  function at(g, px, py) {
    const s = (px * g.scale) / g.kx, lat = g.lat0 - py * g.ky * g.scale;
    for (const f of g.folds) { const a = squeeze(g, f.a); if (s > a && s < a + f.seam) return null; }
    const d = unsqueeze(g, s);
    if (d < g.x0 || d >= g.x1 || lat < g.lo || lat > g.hi) return null;
    return { lat, lon: g.lon0 + d };
  }
  const seams = (g) => g.folds.map((f) => ({ x: ((squeeze(g, f.a) + f.seam / 2) * g.kx) / g.scale, deg: Math.round(f.b - f.a) }));

  // --------------------------------------------------------------- scene
  // GeoScene: sites (one place, or marks that would collide), the worst
  // mark of each, and one arc per pair bowed north.
  const WORSE = { down: 5, degraded: 4, up: 2, unknown: 1, cached: 0 };
  function scene(gr, W, H, ky = 1, samePlace = 60, collide = [12, 10]) {
    const placed = gr.nodes.filter((n) => n.at);
    const v = view(placed.map((n) => n.at), W, H, ky, gr.frame || 'fit');
    const sites = [];
    for (const n of placed) {
      const p = project(v, n.at);
      let s = sites.find((s) => (n.place && (s.places.includes(n.place) || s.cities.includes(n.place)) && Math.abs(s.x - p.x) < samePlace && Math.abs(s.y - p.y) < samePlace)
        || (Math.abs(s.x - p.x) <= collide[0] && Math.abs(s.y - p.y) <= collide[1]));
      if (!s) { s = { x: p.x, y: p.y, pts: [], nodes: [], places: [], cities: [], mark: null, coloOnly: true }; sites.push(s); }
      if (n.place) (n.colo ? s.cities : s.places).includes(n.place) || (n.colo ? s.cities : s.places).push(n.place);
      s.nodes.push(n);
      s.pts.push(p);
      s.coloOnly = s.coloOnly && n.colo;
      s.mark = s.mark == null || WORSE[n.mark] > WORSE[s.mark] ? n.mark : s.mark;
    }
    for (const s of sites) {
      s.x = s.pts.reduce((a, p) => a + p.x, 0) / s.pts.length;
      s.y = s.pts.reduce((a, p) => a + p.y, 0) / s.pts.length;
      const names = s.places.length ? s.places : s.cities;
      s.title = names.length === 1 ? names[0] : names.length === 2 ? names[0] + ' · ' + names[1] : names[0] + ' +' + (names.length - 1);
      s.short = names.length > 1 ? names[0] + ' +' + (names.length - 1) : s.title;
    }
    const siteOf = {};
    sites.forEach((s, i) => s.nodes.forEach((n) => { siteOf[n.id] = i; }));
    const pairs = new Map();
    for (const e of gr.edges) {
      const a = siteOf[e.from], b = siteOf[e.to];
      if (a == null || b == null || a === b) continue;
      const k = Math.min(a, b) + '-' + Math.max(a, b);
      const x = pairs.get(k);
      if (!x) pairs.set(k, { a: Math.min(a, b), b: Math.max(a, b), line: e.line, declared: e.kind === 'link' });
      else { if (RANK[e.line] > RANK[x.line]) x.line = e.line; x.declared = x.declared || e.kind === 'link'; }
    }
    const arcs = [...pairs.values()].map((x) => {
      const p0 = sites[x.a], p3 = sites[x.b];
      const dx = p3.x - p0.x, dy = p3.y - p0.y, l = Math.hypot(dx, dy);
      if (l < 6) return null;
      let nx = -dy / l, ny = dx / l;
      if (ny > 0) { nx = -nx; ny = -ny; }
      const bow = Math.min(l * 0.22, H * 0.3);
      return Object.assign(x, { p0, c: { x: (p0.x + p3.x) / 2 + nx * bow, y: (p0.y + p3.y) / 2 + ny * bow }, p3 });
    }).filter(Boolean);
    return { v, sites, arcs, unplaced: gr.nodes.filter((n) => !n.at) };
  }
  const arcPoint = (a, t) => {
    const u = 1 - t;
    return { x: u * u * a.p0.x + 2 * u * t * a.c.x + t * t * a.p3.x, y: u * u * a.p0.y + 2 * u * t * a.c.y + t * t * a.p3.y };
  };

  // Labels where they cost least: off the bounds, on another, on a mark,
  // across a line. Trouble is named first.
  function placeLabels(reqs, sites, arcs, bounds, keepOut, r, force) {
    const taken = keepOut.slice(), out = {};
    const hit = (a, b) => a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
    const inside = (a) => a.x >= bounds.x && a.y >= bounds.y && a.x + a.w <= bounds.x + bounds.w && a.y + a.h <= bounds.y + bounds.h;
    const lines = arcs.flatMap((a) => [...Array(11)].map((_, k) => arcPoint(a, (k + 1) / 12)));
    reqs.sort((a, b) => (a.trouble !== b.trouble ? (a.trouble ? -1 : 1) : a.y - b.y));
    for (const q of reqs) {
      const { x: cx, y: cy, w, h } = q, g = r + 4;
      const cands = [[cx + g, cy - h / 2], [cx - g - w, cy - h / 2], [cx - w / 2, cy - g - h + 1], [cx - w / 2, cy + g - 1],
        [cx + g * 0.6, cy - g * 0.6 - h], [cx + g * 0.6, cy + g * 0.6], [cx - g * 0.6 - w, cy - g * 0.6 - h], [cx - g * 0.6 - w, cy + g * 0.6]];
      let best = null;
      cands.forEach(([x, y], k) => {
        const rect = { x, y, w, h };
        let cost = k;
        if (!inside(rect)) cost += 1000;
        if (taken.some((t) => hit({ x: t.x - 2, y: t.y - 1, w: t.w + 4, h: t.h + 2 }, rect))) cost += 500;
        for (const s of sites) if (!(s.x === cx && s.y === cy) && s.x > x - r - 2 && s.x < x + w + r + 2 && s.y > y - r - 2 && s.y < y + h + r + 2) cost += 300;
        cost += lines.filter((p) => p.x > x && p.x < x + w && p.y > y && p.y < y + h).length * 3;
        if (!best || cost < best.cost) best = { rect, cost };
      });
      if (!best || best.cost >= 1000 || (best.cost >= 300 && !(q.trouble && force))) continue;
      out[q.i] = best.rect;
      taken.push(best.rect);
    }
    return out;
  }

  const BAYER = [0, 32, 8, 40, 2, 34, 10, 42, 48, 16, 56, 24, 50, 18, 58, 26, 12, 44, 4, 36, 14, 46, 6, 38, 60, 28, 52, 20, 62, 30, 54, 22,
    3, 35, 11, 43, 1, 33, 9, 41, 51, 19, 59, 27, 49, 17, 57, 25, 15, 47, 7, 39, 13, 45, 5, 37, 63, 31, 55, 23, 61, 29, 53, 21];
  const bayer = (i, j) => (BAYER[(((j % 8) + 8) % 8) * 8 + (((i % 8) + 8) % 8)] + 0.5) / 64;
  const smooth = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t); };

  // ------------------------------------------------------- cards painter
  function css(el, name) { return getComputedStyle(el).getPropertyValue(name).trim(); }
  function drawMark(ctx, m, x, y, size, color, on = '#fff') {
    ctx.save();
    ctx.translate(x, y);
    ctx.scale(size / 14, size / 14);
    ctx.fillStyle = color; ctx.strokeStyle = color;
    if (m === 'up') { ctx.beginPath(); ctx.arc(7, 7, 5.2, 0, 7); ctx.fill(); }
    if (m === 'degraded') {
      ctx.beginPath(); ctx.moveTo(6.1, 1.9); ctx.quadraticCurveTo(7, 0.4, 7.9, 1.9); ctx.lineTo(12.9, 11); ctx.quadraticCurveTo(13.6, 12.5, 12, 12.5);
      ctx.lineTo(2, 12.5); ctx.quadraticCurveTo(0.4, 12.5, 1.1, 11); ctx.closePath(); ctx.fill();
      ctx.strokeStyle = on; ctx.lineWidth = 1.4; ctx.lineCap = 'round'; ctx.beginPath(); ctx.moveTo(7, 5.2); ctx.lineTo(7, 8.2); ctx.stroke();
      ctx.fillStyle = on; ctx.beginPath(); ctx.arc(7, 10.2, 0.75, 0, 7); ctx.fill();
    }
    if (m === 'down') {
      ctx.beginPath(); ctx.arc(7, 7, 6, 0, 7); ctx.fill();
      ctx.strokeStyle = on; ctx.lineWidth = 1.5; ctx.lineCap = 'round';
      ctx.beginPath(); ctx.moveTo(4.9, 4.9); ctx.lineTo(9.1, 9.1); ctx.moveTo(9.1, 4.9); ctx.lineTo(4.9, 9.1); ctx.stroke();
    }
    if (m === 'unknown') { ctx.lineWidth = 1.6; ctx.beginPath(); ctx.arc(7, 7, 4.8, 0, 7); ctx.stroke(); }
    if (m === 'cached') { ctx.lineWidth = 1.5; ctx.setLineDash([2.2, 1.9]); ctx.beginPath(); ctx.arc(7, 7, 5, 0, 7); ctx.stroke(); }
    ctx.restore();
  }
  function cardColors(el, o) {
    const dark = o.dark;
    const c = { l1: css(el, '--l1'), l2: css(el, '--l2'), l3: css(el, '--l3'), acc: css(el, '--acc'), up: css(el, '--up'), warn: css(el, '--warn'),
      down: css(el, '--down'), unk: css(el, '--unk'), fill2: css(el, '--fill2') || 'rgba(127,127,127,.12)' };
    const surface = o.tokens === 'aurora' ? 'night' : o.tokens === 'linen' ? 'matte' : 'glass';
    c.land = o.mono ? c.l1 : surface === 'glass' ? (dark ? '#fff' : '#000') : surface === 'night' ? c.acc : c.l1;
    c.strength = { glass: dark ? 0.34 : 0.24, night: dark ? 0.42 : 0.4, matte: dark ? 0.3 : 0.24 }[surface];
    c.mark = (m) => (o.mono ? (m === 'up' ? alpha(c.l1, 0.45) : c.l1) : { up: c.up, degraded: c.warn, down: c.down, unknown: c.unk, cached: c.unk }[m]);
    c.line = (line, declared) => {
      const dash = declared ? [] : [3, 2.6];
      if (o.mono) return { up: [alpha(c.l1, 0.35), 1, dash], carried: [alpha(c.l1, 0.25), 0.9, dash], unknown: [alpha(c.l1, 0.3), 0.85, [1.6, 2.4]], withheld: [alpha(c.l1, 0.3), 0.85, [1.6, 2.4]] }[line] || [c.l1, 1.4, dash];
      return { up: [alpha(c.up, dark ? 0.5 : 0.6), 1, dash], carried: [alpha(c.up, dark ? 0.3 : 0.38), 0.9, dash], affected: [alpha(c.warn, 0.8), 1.2, dash],
        degraded: [c.warn, 1.3, dash], down: [c.down, 1.5, dash], unknown: [alpha(c.unk, 0.6), 0.85, [1.6, 2.4]], withheld: [alpha(c.unk, 0.45), 0.85, [1.6, 2.4]] }[line];
    };
    c.font = getComputedStyle(el).fontFamily;
    return c;
  }
  function alpha(color, a) {
    const ctx = alpha.ctx || (alpha.ctx = document.createElement('canvas').getContext('2d'));
    ctx.fillStyle = '#000'; ctx.fillStyle = color;
    const v = ctx.fillStyle;
    if (v[0] === '#') return `rgba(${parseInt(v.slice(1, 3), 16)},${parseInt(v.slice(3, 5), 16)},${parseInt(v.slice(5, 7), 16)},${a})`;
    const m = v.match(/rgba?\(([^)]+)\)/);
    if (!m) return color;
    const p = m[1].split(',').map((s) => parseFloat(s));
    return `rgba(${p[0]},${p[1]},${p[2]},${(p[3] == null ? 1 : p[3]) * a})`;
  }

  function drawCardsGeo(ctx, W, H, gr, c, o) {
    const sc = scene(gr, W, H);
    const r = 9.5 / 2, detail = o.detail || 'places';
    const bounds = { x: 3, y: 2, w: W - 6, h: H - 4 };
    const font = (size, weight) => `${weight} ${size}px ${c.font}`;
    // Labels first: the land keeps clear of them.
    const made = (nodes, keep, only) => {
      const reqs = [];
      sc.sites.forEach((s, i) => {
        if (s.coloOnly || !s.title || (only && !only.has(i))) return;
        const trouble = s.mark === 'down' || s.mark === 'degraded';
        if (detail === 'marks' && !trouble) return;
        const title = detail === 'marks' ? s.short : s.title;
        ctx.font = font(10, trouble ? 600 : 500);
        let w = ctx.measureText(title).width;
        const rows = [];
        if (nodes) {
          const list = troubleFirst(s.nodes.filter((n) => !n.colo));
          const shown = list.length > 3 ? list.slice(0, 2) : list;
          shown.forEach((n) => rows.push([n.mark, n.name]));
          if (list.length > shown.length) rows.push([list[shown.length].mark, `+${list.length - shown.length} more`]);
          ctx.font = font(9, 400);
          rows.forEach(([, t]) => { w = Math.max(w, ctx.measureText(t).width + 10); });
        }
        reqs.push({ i, x: s.x, y: s.y, w: Math.min(150, w), h: 13 + rows.length * 12, trouble, title, rows });
      });
      const placed = placeLabels(reqs, sc.sites, sc.arcs, bounds, keep, r, detail !== 'marks');
      return reqs.filter((q) => placed[q.i]).map((q) => Object.assign(q, { rect: placed[q.i] }));
    };
    let labels = made(detail === 'nodes', seams(sc.v).map((s) => ({ x: s.x - 24, y: 0, w: 48, h: 14 })));
    const missing = new Set(sc.sites.map((_, i) => i).filter((i) => !labels.some((l) => l.i === i)));
    if (missing.size) labels = labels.concat(made(false, labels.map((l) => l.rect).concat(seams(sc.v).map((s) => ({ x: s.x - 24, y: 0, w: 48, h: 14 }))), missing));
    const clear = labels.map((l) => ({ x: l.rect.x - 2, y: l.rect.y - 1, w: l.rect.w + 4, h: l.rect.h + 2 }));

    // The land: a dot wherever the dither says enough of its cell is land.
    const pitch = 2.6, dot = 1.3, near = r + 2.5;
    ctx.fillStyle = c.land;
    for (let j = -1, y = -pitch; y < H + pitch; j++, y += pitch) {
      for (let i = -1, x = -pitch; x < W + pitch; i++, x += pitch) {
        const cx = x + pitch / 2, cy = y + pitch / 2;
        if (cx <= 0 || cy <= 0 || cx >= W || cy >= H) continue;
        let n = 0, k = 0;
        for (let a = 0; a < 3; a++) for (let b = 0; b < 3; b++) {
          const q = at(sc.v, x + (a + 0.5) * pitch / 3, y + (b + 0.5) * pitch / 3);
          k++; if (q && isLand(q.lat, q.lon)) n++;
        }
        const cover = n / k;
        if (cover <= 0 || cover < bayer(i, j)) continue;
        let nearest = Infinity;
        for (const s of sc.sites) nearest = Math.min(nearest, Math.hypot(s.x - cx, s.y - cy));
        if (nearest <= near || clear.some((q) => cx > q.x && cx < q.x + q.w && cy > q.y && cy < q.y + q.h)) continue;
        const fade = smooth(0, 14, Math.min(cx, W - cx, cy, H - cy)), glow = Math.exp(-nearest / 56);
        const a = fade * (0.42 + 0.58 * glow);
        const level = Math.min(7, Math.floor(a * 8));
        if (level <= 0) continue;
        ctx.globalAlpha = Math.min(1, c.strength * ((level + 0.5) / 8) * 1.5);
        const d = dot * (0.8 + 0.2 * cover + 0.25 * glow);
        ctx.beginPath(); ctx.arc(cx, cy, d / 2, 0, 7); ctx.fill();
      }
    }
    ctx.globalAlpha = 1;
    // Seams, headed by the degrees they hold.
    for (const s of seams(sc.v)) {
      if (s.x <= 0 || s.x >= W) continue;
      ctx.fillStyle = alpha(c.l3, 0.6);
      for (let y = 18; y < H - 4; y += 3) ctx.fillRect(s.x - 0.5, y, 1, 1);
      ctx.fillStyle = c.l3; ctx.font = font(8.5, 500); ctx.textAlign = 'center'; ctx.textBaseline = 'top';
      ctx.fillText(s.deg + '°', s.x, 4);
      ctx.textAlign = 'left';
    }
    // Arcs, the calm under the troubled, trimmed clear of the marks.
    for (const a of sc.arcs.slice().sort((x, y) => RANK[x.line] - RANK[y.line])) {
      const [color, width, dash] = c.line(a.line, a.declared);
      ctx.strokeStyle = color; ctx.lineWidth = width; ctx.lineCap = 'round'; ctx.setLineDash(dash);
      ctx.beginPath();
      let started = false;
      for (let k = 0; k <= 48; k++) {
        const p = arcPoint(a, k / 48);
        if (Math.hypot(p.x - a.p0.x, p.y - a.p0.y) < r + 2.5 || Math.hypot(p.x - a.p3.x, p.y - a.p3.y) < r + 2.5) continue;
        if (!started) { ctx.moveTo(p.x, p.y); started = true; } else ctx.lineTo(p.x, p.y);
      }
      ctx.stroke();
    }
    ctx.setLineDash([]);
    // Each place: a quiet ring, a second for trouble, and its mark.
    for (const s of sc.sites) {
      const color = c.mark(s.mark);
      ctx.lineWidth = 0.75;
      if (s.coloOnly) { ctx.strokeStyle = s.mark === 'up' ? color : c.unk; ctx.lineWidth = 1; ctx.beginPath(); ctx.arc(s.x, s.y, 3, 0, 7); ctx.stroke(); continue; }
      const trouble = s.mark === 'down' || s.mark === 'degraded';
      ctx.strokeStyle = alpha(color, trouble ? 0.5 : 0.3); ctx.beginPath(); ctx.arc(s.x, s.y, r + 3, 0, 7); ctx.stroke();
      if (trouble) { ctx.strokeStyle = alpha(color, 0.18); ctx.beginPath(); ctx.arc(s.x, s.y, r + 7, 0, 7); ctx.stroke(); }
      drawMark(ctx, s.mark, s.x - r, s.y - r, 9.5, color);
    }
    // Names.
    ctx.textBaseline = 'top';
    for (const l of labels) {
      const left = l.rect.x + l.rect.w / 2 >= l.x - 1;
      ctx.font = font(10, l.trouble ? 600 : 500); ctx.fillStyle = o.mono || l.trouble ? c.l1 : c.l2;
      const tw = ctx.measureText(l.title).width;
      ctx.fillText(l.title, left ? l.rect.x : l.rect.x + l.rect.w - tw, l.rect.y + 0.5);
      l.rows.forEach(([m, t], k) => {
        ctx.font = font(9, 400);
        const w = ctx.measureText(t).width, y = l.rect.y + 13 + k * 12;
        const x = left ? l.rect.x : l.rect.x + l.rect.w - w - 9.5;
        drawMark(ctx, m, x, y + 2.75, 6.5, c.mark(m));
        ctx.fillStyle = c.l3; ctx.fillText(t, x + 9.5, y + 1);
      });
    }
  }

  // The virtual view: places as cards west to east, wired row to row.
  // A simpler layout than VirtualScene's, with its look.
  function virtualLayout(gr, W, H, measure, m, sizeOf) {
    const sc = scene(Object.assign({}, gr, { frame: 'fit' }), 1000, 400, 1, 2, [0.5, 0.5]);
    const [centre, arc] = lonBounds(sc.sites.map((s) => s.nodes[0].at.lon));
    const key = (s) => (((s.nodes[0].at.lon - (centre - arc / 2) + 720 + 1e-6) % 360));
    const cards = sc.sites.filter((s) => !s.coloOnly).map((s) => ({ title: s.places[0] || s.cities[0], nodes: s.nodes.filter((n) => !n.colo), mark: s.mark, key: key(s), lat: s.nodes[0].at.lat }))
      .concat(sc.unplaced.map((n) => ({ title: '', nodes: [n], mark: n.mark, pill: true, lat: null })));
    cards.forEach((c) => {
      c.w = c.pill ? measure(c.nodes[0].name, false) + m.mark + 2 * m.padX : Math.max(measure(c.title, true), Math.min(6, c.nodes.length) * m.chip) + 2 * m.padX;
      c.h = c.pill ? m.pill : m.title + m.row + 2 * m.padY - 2;
      if (sizeOf) sizeOf(c);
    });
    const places = cards.filter((c) => !c.pill).sort((a, b) => a.key - b.key);
    // Columns at the widest gaps of longitude, as many as fit.
    const gaps = places.slice(1).map((c, i) => [c.key - places[i].key, i + 1]).sort((a, b) => b[0] - a[0]);
    let cols = [];
    for (let nc = places.length; nc >= 1; nc--) {
      const cuts = new Set(gaps.slice(0, nc - 1).map((g) => g[1]));
      cols = [[]];
      places.forEach((c, i) => { if (cuts.has(i)) cols.push([]); cols[cols.length - 1].push(c); });
      const width = cols.reduce((a, col) => a + Math.max(...col.map((c) => c.w)), 0) + (cols.length - 1) * m.gap + 2 * m.margin;
      if (width <= W - (nc > 1 ? 0 : 0)) break;
    }
    // A card without a place joins the column it links to most, by room.
    const colOf = new Map();
    cols.forEach((col, k) => col.forEach((c) => c.nodes.forEach((n) => colOf.set(n.id, k))));
    for (const c of cards.filter((c) => c.pill)) {
      const linked = gr.edges.filter((e) => e.from === c.nodes[0].id || e.to === c.nodes[0].id).map((e) => colOf.get(e.from === c.nodes[0].id ? e.to : e.from)).filter((k) => k != null);
      const room = (k) => H - cols[k].reduce((a, x) => a + x.h + m.cardGap, 0);
      let k = linked.length ? linked.sort((a, b) => room(b) - room(a))[0] : cols.length - 1;
      if (room(k) < c.h) k = cols.map((_, i) => i).sort((a, b) => room(b) - room(a))[0];
      cols[k].push(c);
      colOf.set(c.nodes[0].id, k);
    }
    const widths = cols.map((col) => Math.max(...col.map((c) => c.w)));
    const spare = Math.max(0, W - widths.reduce((a, b) => a + b, 0) - 2 * m.margin);
    let x = cols.length > 1 ? m.margin : (W - widths[0]) / 2;
    const gap = cols.length > 1 ? spare / (cols.length - 1) : 0;
    cols.forEach((col, k) => {
      col.sort((a, b) => (b.lat == null ? -999 : b.lat) - (a.lat == null ? -999 : a.lat));
      const total = col.reduce((a, c) => a + c.h, 0) + (col.length - 1) * m.cardGap;
      let y = Math.max(m.margin, (H - total) / 2);
      for (const c of col) { c.x = x + (widths[k] - c.w) / 2; c.y = y; y += c.h + m.cardGap; c.col = k; }
      x += widths[k] + gap;
    });
    // One wire per pair of cards, the worst line between them.
    const cardOf = new Map();
    cards.forEach((c) => c.nodes.forEach((n) => cardOf.set(n.id, c)));
    sc.sites.forEach((s) => s.nodes.forEach((n) => { if (n.colo && !cardOf.has(n.id)) cardOf.set(n.id, cards.find((c) => !c.pill && c.title === n.place)); }));
    const wires = new Map();
    for (const e of gr.edges) {
      const a = cardOf.get(e.from), b = cardOf.get(e.to);
      if (!a || !b || a === b) continue;
      const k = [cards.indexOf(a), cards.indexOf(b)].sort((p, q) => p - q).join('-');
      const w = wires.get(k);
      if (!w) wires.set(k, { a, b, line: e.line, declared: e.kind === 'link' });
      else { if (RANK[e.line] > RANK[w.line]) w.line = e.line; w.declared = w.declared || e.kind === 'link'; }
    }
    return { cards, wires: [...wires.values()] };
  }
  function drawCardsVirtual(ctx, W, H, gr, c, o) {
    // A faint field of the land's dots, as the geo map's lattice.
    ctx.fillStyle = alpha(c.land, c.strength * 0.35);
    for (let y = 6; y < H; y += 9) for (let x = 6; x < W; x += 9) { ctx.beginPath(); ctx.arc(x, y, 0.55, 0, 7); ctx.fill(); }
    const font = (size, weight, track) => `${weight} ${size}px ${c.font}`;
    const measure = (t, title) => { ctx.font = title ? font(8.5, 600) : font(10, 500); return ctx.measureText(title ? t.toUpperCase() : t).width + (title ? t.length * 0.6 : 0); };
    const m = { padX: 7, padY: 5, title: 14, row: 14, pill: 19, mark: 12, chip: 9, gap: 22, cardGap: 9, margin: 9 };
    let L = virtualLayout(gr, W, H, measure, m);
    // Too tall: each place on one line, its name beside its marks.
    const chips = L.cards.some((c) => c.y + c.h > H - 2);
    if (chips) {
      L = virtualLayout(gr, W, H, measure, Object.assign({}, m, { cardGap: 3, margin: 3 }), (c) => {
        c.h = m.pill;
        if (!c.pill) c.w = measure(c.title, true) + 5 + Math.min(6, c.nodes.length) * m.chip + 2 * m.padX;
      });
    }
    const side = (a, b) => (a.x + a.w / 2 < b.x + b.w / 2 ? [1, -1] : a.x + a.w / 2 > b.x + b.w / 2 ? [-1, 1] : [1, 1]);
    for (const w of L.wires.sort((x, y) => RANK[x.line] - RANK[y.line])) {
      const [sa, sb] = side(w.a, w.b);
      const p0 = { x: sa > 0 ? w.a.x + w.a.w : w.a.x, y: w.a.y + w.a.h / 2 }, p3 = { x: sb > 0 ? w.b.x + w.b.w : w.b.x, y: w.b.y + w.b.h / 2 };
      const k = Math.max(18, Math.abs(p3.x - p0.x) * 0.45);
      const [color, width, dash] = c.line(w.line, w.declared);
      ctx.strokeStyle = color; ctx.lineWidth = width; ctx.setLineDash(dash);
      ctx.beginPath(); ctx.moveTo(p0.x, p0.y); ctx.bezierCurveTo(p0.x + sa * k, p0.y, p3.x + sb * k, p3.y, p3.x, p3.y); ctx.stroke();
      ctx.setLineDash([]);
      ctx.fillStyle = color;
      for (const p of [p0, p3]) { ctx.beginPath(); ctx.arc(p.x, p.y, 1.6, 0, 7); ctx.fill(); }
    }
    for (const card of L.cards) {
      const trouble = card.mark === 'down' || card.mark === 'degraded';
      const color = c.mark(card.mark);
      ctx.beginPath(); ctx.roundRect(card.x, card.y, card.w, card.h, card.pill ? card.h / 2 : 6);
      ctx.fillStyle = o.dark ? 'rgba(30,30,34,.92)' : 'rgba(250,250,252,.95)'; ctx.fill();
      ctx.fillStyle = c.fill2; ctx.fill();
      ctx.strokeStyle = trouble ? alpha(color, 0.65) : alpha(c.l3, 0.5); ctx.lineWidth = trouble ? 1 : 0.6; ctx.stroke();
      ctx.textBaseline = 'middle';
      if (card.pill) {
        const n = card.nodes[0];
        drawMark(ctx, n.mark, card.x + m.padX, card.y + card.h / 2 - 4, 8, c.mark(n.mark));
        ctx.font = font(10, 500); ctx.fillStyle = c.l2; ctx.fillText(n.name, card.x + m.padX + m.mark, card.y + card.h / 2 + 0.5);
        continue;
      }
      ctx.font = font(8.5, 600); ctx.fillStyle = trouble ? c.l1 : c.l2;
      ctx.letterSpacing = '0.6px';
      ctx.fillText(card.title.toUpperCase(), card.x + m.padX, chips ? card.y + card.h / 2 + 0.5 : card.y + m.padY + m.title / 2);
      ctx.letterSpacing = '0px';
      const mx = chips ? card.x + card.w - m.padX - Math.min(6, card.nodes.length) * m.chip : card.x + m.padX;
      const my = chips ? card.y + card.h / 2 - 3.75 : card.y + m.padY + m.title + 1;
      card.nodes.slice(0, 6).forEach((n, k) => drawMark(ctx, n.mark, mx + k * m.chip, my, 7.5, c.mark(n.mark)));
    }
  }

  // ------------------------------------------------------- cells painter
  // The TUI's map: land shaded cell by cell under braille dots with a
  // dotted coast, marks and names in the grid, arcs in dots.
  function drawCellsGeo(ctx, cols, rows, cw, lh, gr, P, o) {
    const W = cols * 2, H = rows * 4, ky = (lh / 4) / (cw / 2);
    const sc = scene(gr, W, H, ky, 24, [5, 4]);
    const dw = cw / 2, dh = lh / 4;
    const grid = new Uint8Array(W * H);
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) { const q = at(sc.v, x + 0.5, y + 0.5); if (q && isLand(q.lat, q.lon)) grid[y * W + x] = 1; }
    const land = TB.mix(P.ink, P.acc, 0.09), lattice = TB.mix(P.ink, P.acc, 0.24), coast = TB.mix(P.ink, P.acc, 0.42);
    for (let cy = 0; cy < rows; cy++) for (let cx = 0; cx < cols; cx++) {
      let n = 0;
      for (let k = 0; k < 8; k++) n += grid[(cy * 4 + (k >> 1)) * W + cx * 2 + (k & 1)];
      if (!n) continue;
      ctx.fillStyle = TB.mix(P.ink, land, n / 8); ctx.fillRect(cx * cw, cy * lh, cw + 0.3, lh + 0.3);
    }
    const dots = new Map();
    const set = (x, y, color, pri) => { if (x < 0 || y < 0 || x >= W || y >= H) return; const k = y * W + x; const d = dots.get(k); if (!d || d[1] <= pri) dots.set(k, [color, pri]); };
    const L = (x, y) => (x >= 0 && y >= 0 && x < W && y < H ? grid[y * W + x] : 0);
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
      if (!grid[y * W + x]) continue;
      if (!L(x - 1, y) || !L(x + 1, y) || !L(x, y - 1) || !L(x, y + 1)) set(x, y, coast, 1);
      else if (x % 2 === 0 && y % 2 === 0) set(x, y, lattice, 1);
    }
    for (const s of seams(sc.v)) for (let y = 0; y < H; y += 2) set(Math.floor(s.x), y, TB.mix(P.line, P.acc, 0.2), 1);
    const tone = (m) => ({ up: P.up, degraded: P.warn, down: P.down, unknown: P.unk, cached: P.unk }[m]);
    const lineTone = (l) => ({ up: TB.mix(P.up, P.ink, 0.5), carried: TB.mix(P.up, P.ink, 0.62), affected: P.warn, degraded: P.warn, down: P.down }[l] || TB.mix(P.unk, P.ink, 0.3));
    for (const a of sc.arcs.slice().sort((x, y) => RANK[x.line] - RANK[y.line])) {
      const n = Math.max(2, Math.round(Math.hypot(a.p3.x - a.p0.x, a.p3.y - a.p0.y) * 1.3));
      for (let k = 0; k <= n; k++) {
        const p = arcPoint(a, k / n);
        if ((Math.abs(p.x - a.p0.x) <= 2.5 && Math.abs(p.y - a.p0.y) <= 3) || (Math.abs(p.x - a.p3.x) <= 2.5 && Math.abs(p.y - a.p3.y) <= 3)) continue;
        if (!a.declared && k % 3 === 2) continue;
        set(Math.round(p.x), Math.round(p.y), lineTone(a.line), 2 + RANK[a.line]);
      }
    }
    // Text cells clear the dots under them.
    const texts = [];
    const taken = new Set();
    const tag = ' ' + (gr.frame || 'fit') + ' ';
    texts.push([cols - tag.length - 1, 0, tag, P.faint, false]);
    for (const s of seams(sc.v)) {
      const label = ' ' + s.deg + '° folded ';
      const lx = Math.floor(s.x / 2 - label.length / 2);
      if (lx >= 0 && lx + label.length < cols - tag.length - 1) texts.push([lx, 0, label, P.faint, false]);
    }
    const sites = sc.sites.slice().sort((a, b) => WORSE[b.mark] - WORSE[a.mark]);
    for (const s of sites) taken.add(Math.floor(s.y / 4) * cols + Math.floor(s.x / 2));
    for (const s of sites) {
      const cx = Math.floor(s.x / 2), cy = Math.floor(s.y / 4);
      texts.push([cx, cy, s.coloOnly ? '·' : TB.glyph(s.mark === 'cached' ? 'cached' : s.mark), s.coloOnly ? TB.mix(P.up, P.ink, 0.4) : tone(s.mark), s.mark === 'down' || s.mark === 'degraded']);
      if (s.coloOnly) continue;
      const trouble = s.mark === 'down' || s.mark === 'degraded';
      // With room for marks alone, only trouble is named, by its first place.
      if (o.detail === 'marks' && !trouble) continue;
      const names = o.detail === 'marks' ? [s.short] : [s.title, s.short].filter((t, i, a) => a.indexOf(t) === i);
      // Beside its mark, else above or below it, a cell clear each side.
      const free = (x, y, n) => x >= 0 && x + n <= cols && y >= 0 && y < rows && ![...Array(n + 2)].some((_, i) => taken.has(y * cols + x - 1 + i));
      let spot = null;
      for (const name of names) {
        const n = name.length;
        spot = [[cx + 2, cy], [cx - 1 - n, cy], [cx - (n >> 1), cy - 1], [cx - (n >> 1), cy + 1]].find(([x, y]) => free(x, y, n));
        if (spot) { spot.push(name); break; }
      }
      if (!spot) continue;
      const [x, y, name] = spot;
      for (let i = -1; i <= name.length; i++) taken.add(y * cols + x + i);
      texts.push([x, y, name, trouble ? P.text : P.muted, trouble]);
    }
    for (const [x, y, t] of texts) for (let i = 0; i < t.length; i++) for (let k = 0; k < 8; k++) dots.delete((y * 4 + (k >> 1)) * W + (x + i) * 2 + (k & 1));
    for (const [k, [color]] of dots) {
      const x = k % W, y = Math.floor(k / W);
      ctx.fillStyle = color; ctx.beginPath(); ctx.arc(x * dw + dw / 2, y * dh + dh / 2, Math.min(dw, dh) * 0.3, 0, 7); ctx.fill();
    }
    ctx.textBaseline = 'middle';
    for (const [x, y, t, color, bold] of texts) {
      ctx.font = `${bold ? 700 : 400} 12px ui-monospace, "SF Mono", Menlo, monospace`; ctx.fillStyle = color;
      [...t].forEach((ch, i) => ctx.fillText(ch, x * cw + i * cw, y * lh + lh / 2 + 0.5));
    }
  }
  // CellsVirtual: each place a chip on one line, in columns west to east
  // split at gaps of 12° and more while they fit, each on the line its
  // latitude puts it; pills in the column they link to most.
  function cellsLayout(gr, cols, rows) {
    const cards = [], cardOf = {};
    for (const n of gr.nodes.filter((n) => n.at && !n.colo)) {
      let k = cards.findIndex((c) => !c.pill && (c.title === n.place || (Math.abs(c.lat - n.at.lat) < 0.5 && Math.abs(c.lon - n.at.lon) < 0.5)));
      if (k < 0) { k = cards.length; cards.push({ title: n.place, nodes: [], pill: false, lat: n.at.lat, lon: n.at.lon }); }
      cards[k].nodes.push(n); cardOf[n.id] = k;
    }
    for (const n of gr.nodes.filter((n) => n.colo)) { const k = cards.findIndex((c) => c.title === n.place); if (k >= 0) cardOf[n.id] = k; }
    for (const n of gr.nodes.filter((n) => !n.at)) { cardOf[n.id] = cards.length; cards.push({ title: n.name, nodes: [n], pill: true }); }
    const mark = (c) => c.nodes.reduce((m, n) => (m == null || WORSE[n.mark] > WORSE[m] ? n.mark : m), null);
    cards.forEach((c) => { c.mark = mark(c); c.w = c.pill ? 2 + len(c.title) + 2 : len(c.title) + 1 + Math.min(4, c.nodes.length) + 2; });
    const pairs = new Map();
    for (const e of gr.edges) {
      const a = cardOf[e.from], b = cardOf[e.to];
      if (a == null || b == null || a === b) continue;
      const k = Math.min(a, b) + '-' + Math.max(a, b), w = pairs.get(k);
      if (!w) pairs.set(k, { a: Math.min(a, b), b: Math.max(a, b), line: e.line, declared: e.kind === 'link' });
      else { if (RANK[e.line] > RANK[w.line]) w.line = e.line; w.declared = w.declared || e.kind === 'link'; }
    }
    const wires = [...pairs.values()];
    const near = cards.map(() => []);
    wires.forEach((w) => { near[w.a].push(w.b); near[w.b].push(w.a); });
    const places = cards.map((_, i) => i).filter((i) => !cards[i].pill);
    const pills = cards.map((_, i) => i).filter((i) => cards[i].pill).sort((a, b) => near[b].length - near[a].length || cards[b].w - cards[a].w);
    const [centre, arc] = lonBounds(places.map((k) => cards[k].lon));
    const key = (k) => (cards[k].lon - (centre - arc / 2) + 720 + 1e-6) % 360;
    const order = places.slice().sort((a, b) => key(a) - key(b));
    const gaps = order.slice(1).map((k, i) => i).sort((a, b) => (key(order[b + 1]) - key(order[b])) - (key(order[a + 1]) - key(order[a])));
    const GAP = 2;
    function attempt(nc) {
      const cuts = new Set(gaps.slice(0, nc - 1).map((g) => g + 1));
      const col = {};
      let c = 0;
      order.forEach((k, i) => { if (cuts.has(i)) c++; col[k] = c; });
      const n = c + 1, w = Array(n).fill(0), count = Array(n).fill(0);
      places.forEach((k) => { w[col[k]] = Math.max(w[col[k]], cards[k].w); count[col[k]]++; });
      const room = cols - GAP * (n - 1);
      const sum = () => w.reduce((a, b) => a + b, 0);
      if (sum() > room || count.some((x) => x > rows)) return null;
      for (const p of pills) {
        const options = [...Array(n).keys()].filter((c) => count[c] < rows && sum() - w[c] + Math.max(w[c], cards[p].w) <= room);
        if (!options.length) return null;
        const cost = (c) => (Math.max(w[c], cards[p].w) - w[c]) * 10 - near[p].filter((k) => col[k] === c).length * 3 + count[c];
        const best = options.sort((a, b) => cost(a) - cost(b))[0];
        col[p] = best; w[best] = Math.max(w[best], cards[p].w); count[best]++;
      }
      return { col, n, w };
    }
    const regions = 1 + order.slice(1).filter((k, i) => key(k) - key(order[i]) >= 12).length;
    const most = Math.min(order.length, Math.max(1, Math.floor(cols / 9)));
    let L = null;
    for (let nc = Math.min(regions, most); nc >= 1 && !L; nc--) L = attempt(nc);
    for (let nc = most; nc > regions && !L; nc--) L = attempt(nc);
    if (!L) return { cards: [], wires: [] };
    const lats = places.map((k) => cards[k].lat), top = Math.max(...lats), bottom = Math.min(...lats);
    const north = (k) => (cards[k].pill ? (near[k].filter((j) => !cards[j].pill).map((j) => cards[j].lat).reduce((a, b, _, x) => a + b / x.length, 0) || -1000) - 500 : cards[k].lat);
    const spare = Math.max(0, cols - L.w.reduce((a, b) => a + b, 0));
    const margin = L.n > 1 ? Math.min(2, Math.floor(spare / (L.n + 1))) : Math.floor((cols - L.w[0]) / 2);
    const between = L.n > 1 ? Math.floor((spare - 2 * margin) / (L.n - 1)) : 0;
    let x = margin;
    for (let c = 0; c < L.n; c++) {
      const list = cards.map((_, i) => i).filter((i) => L.col[i] === c).sort((a, b) => north(b) - north(a));
      const gap = 2 * list.length - 1 <= rows ? 2 : 1;
      const want = list.map((k) => (cards[k].pill || top === bottom ? Math.floor(rows / 2) : Math.round(((top - cards[k].lat) / (top - bottom)) * (rows - 1))));
      for (let i = 1; i < want.length; i++) want[i] = Math.max(want[i], want[i - 1] + gap);
      if (want[want.length - 1] > rows - 1) { want[want.length - 1] = rows - 1; for (let i = want.length - 2; i >= 0; i--) want[i] = Math.min(want[i], want[i + 1] - gap); }
      list.forEach((k, i) => { cards[k].col = c; cards[k].row = Math.max(0, want[i]); cards[k].x = x + Math.floor((L.w[c] - cards[k].w) / 2); });
      x += L.w[c] + between;
    }
    return { cards, wires, last: L.n - 1 };
  }
  const len = (s) => [...s].length;
  function drawCellsVirtual(ctx, cols, rows, cw, lh, gr, P) {
    const L = cellsLayout(gr, cols, rows);
    const rect = (c) => ({ x: c.x * cw, y: c.row * lh, w: c.w * cw, h: lh });
    const tone = (m) => ({ up: P.up, degraded: P.warn, down: P.down, unknown: P.unk, cached: P.unk }[m]);
    const lineTone = (l) => ({ up: TB.mix(P.up, P.ink, 0.5), carried: TB.mix(P.up, P.ink, 0.62), affected: P.warn, degraded: P.warn, down: P.down }[l] || TB.mix(P.unk, P.ink, 0.3));
    const dw = cw / 2;
    for (const w of L.wires.slice().sort((x, y) => RANK[x.line] - RANK[y.line])) {
      const a = L.cards[w.a], b = L.cards[w.b], ra = rect(a), rb = rect(b);
      const [sa, sb] = a.col === b.col ? (a.col === L.last && L.last > 0 ? [-1, -1] : [1, 1]) : a.col < b.col ? [1, -1] : [-1, 1];
      const p0 = { x: sa > 0 ? ra.x + ra.w + 1 : ra.x - 1, y: ra.y + lh / 2 }, p3 = { x: sb > 0 ? rb.x + rb.w + 1 : rb.x - 1, y: rb.y + lh / 2 };
      const reach = Math.max(2 * cw, Math.abs(p3.x - p0.x) * 0.45);
      const p1 = { x: p0.x + sa * reach, y: p0.y }, p2 = { x: p3.x + sb * reach, y: p3.y };
      const n = Math.max(2, Math.round((Math.hypot(p3.x - p0.x, p3.y - p0.y) + 2 * reach) / dw));
      ctx.fillStyle = lineTone(w.line);
      for (let i = 0; i <= n; i++) {
        if (!w.declared && i % 3 === 2) continue;
        const t = i / n, u = 1 - t;
        const x = u * u * u * p0.x + 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t * p3.x;
        const y = u * u * u * p0.y + 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t * p3.y;
        if (L.cards.some((c) => c.x != null && x > c.x * cw - 0.5 && x < (c.x + c.w) * cw + 0.5 && y > c.row * lh + 1 && y < (c.row + 1) * lh - 1)) continue;
        ctx.beginPath(); ctx.arc(x, y, Math.min(dw, lh / 4) * 0.3, 0, 7); ctx.fill();
      }
    }
    ctx.textBaseline = 'middle';
    for (const c of L.cards) {
      if (c.x == null) continue;
      const r = rect(c), trouble = c.mark === 'down' || c.mark === 'degraded';
      ctx.fillStyle = c.pill ? TB.mix(P.ink, tone(c.mark), 0.16) : P.key;
      ctx.beginPath(); ctx.roundRect(r.x, r.y + 1, r.w, lh - 2, 4); ctx.fill();
      let x = r.x + cw;
      const put = (t, color, bold) => { ctx.font = `${bold ? 700 : 400} 12px ui-monospace, "SF Mono", Menlo, monospace`; ctx.fillStyle = color; [...t].forEach((ch) => { ctx.fillText(ch, x, r.y + lh / 2 + 0.5); x += cw; }); };
      if (c.pill) { put(TB.glyph(c.mark), tone(c.mark)); put(' ' + c.title, P.text); continue; }
      put(c.title, trouble ? P.text : P.muted, trouble);
      put(' ', P.text);
      c.nodes.slice(0, 4).forEach((n) => put(TB.glyph(n.mark === 'cached' ? 'cached' : n.mark), tone(n.mark)));
    }
  }

  // ---------------------------------------------------------- canvases
  function draw(cv) {
    const o = JSON.parse(cv.dataset.map);
    const gr = Object.assign(graph(o.scenario), { frame: o.frame || 'fit' });
    const W = cv.clientWidth || +cv.getAttribute('width'), H = cv.clientHeight || +cv.getAttribute('height');
    const dpr = window.devicePixelRatio || 1;
    cv.width = Math.round(W * dpr); cv.height = Math.round(H * dpr);
    const ctx = cv.getContext('2d');
    ctx.scale(dpr, dpr);
    if (o.look === 'cells') {
      const P = TB.palettes[o.palette || 'terminal'];
      ctx.font = '12px ui-monospace, "SF Mono", Menlo, monospace';
      const cw = ctx.measureText('0').width, lh = 18;
      const cols = Math.round(W / cw), rows = Math.round(H / lh);
      if (o.mode === 'virtual') drawCellsVirtual(ctx, cols, rows, cw, lh, gr, P);
      else drawCellsGeo(ctx, cols, rows, cw, lh, gr, P, o);
    } else {
      const c = cardColors(cv, o);
      if (o.mode === 'virtual') drawCardsVirtual(ctx, W, H, gr, c, o);
      else drawCardsGeo(ctx, W, H, gr, c, o);
    }
    cv.dataset.drawn = '1';
  }
  TB.drawMaps = (root = document) => root.querySelectorAll('canvas[data-map]:not([data-drawn])').forEach(draw);
  new MutationObserver(() => TB.drawMaps()).observe(document.documentElement, { childList: true, subtree: true });
  window.addEventListener('load', () => TB.drawMaps());

  const canvas = (o, w, h, cls = '') => `<canvas class="map-cv ${cls}" style="width:${w ? w + 'px' : '100%'};height:${h}px" data-map='${JSON.stringify(o)}'></canvas>`;

  // ------------------------------------------------------------- pieces
  /// The Map card: its title and the switch, the map full width, and what
  /// it can't place beneath.
  TB.nvMap = function (sc, o) {
    const mode = o.mapMode || 'geo', gr = graph(sc.key);
    const sw = `<span class="map-sw">${['geo', 'virtual'].map((m) => `<b class="${m === mode ? 'on' : ''}">${m === 'geo' ? 'Geo' : 'Virtual'}</b>`).join('')}</span>`;
    const unplaced = troubleFirst(gr.nodes.filter((n) => !n.at));
    const foot = [mode === 'geo' && unplaced.length ? `<span>${unplaced.length} without a location <i>${unplaced.map((n) => TB._cards.mark(n.mark, 8)).join('')}</i></span>` : '',
      gr.current ? '' : '<span class="r">not current</span>'].join('');
    return `<section class="nv-card nv-map"><h3>${TB._cards.I.map || mapIcon}Map${sw}</h3>
      ${canvas({ scenario: sc.key, mode, frame: o.mapFrame || 'fit', dark: o.appearance === 'dark', tokens: o.tokens || '' }, 328, 172)}
      ${foot ? `<div class="map-foot">${foot}</div>` : ''}</section>`;
  };
  const mapIcon = '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round"><path d="M2.5 5l5-2 5 2 5-2v12l-5 2-5-2-5 2z"/><path d="M7.5 3v12M12.5 5v12"/></svg>';

  /// The Terminal box: MAP · geo virtual in its border, the places counted.
  TB.tvMap = function (sc, o, T) {
    const S = T.S, mode = o.mapMode || 'geo', gr = graph(sc.key);
    const title = [S(' MAP', 'acc b'), S(' · ', 'faint'), S('geo', mode === 'geo' ? 'b' : 'faint'), S(' ', 'faint'), S('virtual', mode === 'virtual' ? 'b' : 'faint'), S(' ')];
    const unplaced = troubleFirst(gr.nodes.filter((n) => !n.at));
    let tray = '';
    if (mode === 'geo' && unplaced.length) {
      const segs = [S('no location ', 'faint')];
      let used = 12;
      for (let i = 0; i < unplaced.length; i++) {
        const name = unplaced[i].name + '  ';
        if (used + 2 + name.length + (unplaced.length - i > 1 ? 4 : 0) > 46) { segs.push(S('+' + (unplaced.length - i), 'faint')); break; }
        segs.push(S(TB.glyph(unplaced[i].mark), 'h-' + TB.cls(unplaced[i].mark)), S(' ' + name, 'muted'));
        used += 2 + name.length;
      }
      tray = T.tl(segs, gr.current ? [] : [S('not current', 'faint')]);
    }
    const body = `<div class="tl map-tl" style="height:${9 * 18}px">${canvas({ scenario: sc.key, mode, frame: o.mapFrame || 'fit', look: 'cells', palette: o.palette || 'terminal' }, 0, 9 * 18, 'map-cells')}</div>${tray}`;
    return T.box(title, [S(` ${placesOf(gr).length} places `, 'muted')], body);
  };

  /// The Map widget: the map across the whole widget under its heading.
  TB.mapWidget = function (size, sc, o) {
    const SIZE = TB.widgetSize[size];
    const gr = graph(sc.key), mode = o.mapMode || 'geo';
    const detail = { s: 'marks', m: 'places', l: 'nodes', xl: 'nodes' }[size];
    if (o.theme === 'tui') {
      const P = TB.palettes[o.palette || 'terminal'];
      const rows = Math.floor((SIZE[1] - 16 - 40) / 18);
      const T = TB._cells, S = T.S, cols = { s: 22, m: 51, l: 51, xl: 108 }[size];
      const head = T.tl([S('◉', 'acc'), S(' homelab', 'b')], [sc.live ? S('● LIVE', 'h-up b') : S('◌', 'h-unk b')], 'whead', cols);
      const title = size === 's' ? [S(' MAP ', 'acc b')]
        : [S(' MAP', 'acc b'), S(' · ', 'faint'), S('geo', mode === 'geo' ? 'b' : 'faint'), S(' ', 'faint'), S('virtual', mode === 'virtual' ? 'b' : 'faint'), S(' ')];
      const map = `<div class="tl map-tl" style="height:${rows * 18}px">${canvas({ scenario: sc.key, mode, frame: o.mapFrame || 'fit', look: 'cells', palette: o.palette || 'terminal', detail }, 0, rows * 18, 'map-cells')}</div>`;
      return `<div class="wdg tv wd-${size}" style="${TB.paletteVars(P)};width:${SIZE[0]}px;height:${SIZE[1]}px">${head}${T.box(title, size === 's' ? null : [S(` ${placesOf(gr).length} places `, 'muted')], map)}</div>`;
    }
    const unplaced = troubleFirst(gr.nodes.filter((n) => !n.at));
    const h = SIZE[1] - 30 - 26;
    return `<div class="wdg nv ${o.appearance} wd-${size} map-w" style="${TB.tokenCSS(o)}width:${SIZE[0]}px;height:${SIZE[1]}px">
      <div class="map-w-h">${mapIcon}<b>Map</b>${size === 's' ? '' : `<span>${mode === 'virtual' ? 'Virtual · ' : ''}${placesOf(gr).length} places</span>`}<img class="w-mark" src="assets/mark.svg" alt=""></div>
      ${canvas({ scenario: sc.key, mode, frame: o.mapFrame || 'fit', dark: o.appearance === 'dark', tokens: o.tokens || '', detail }, SIZE[0], h)}
      <div class="map-w-f">${mode === 'geo' && unplaced.length && size !== 's' ? `<span>${unplaced.length} without a location<i>${unplaced.slice(0, 6).map((n) => TB._cards.mark(n.mark, 7.5)).join('')}</i></span>` : '<span></span>'}<span>${gr.current ? esc(sc.age || 'now') : 'Not current'}</span></div></div>`;
  };
})();
