// Topophany Bar design preview: draws the status item, the panel in either
// theme, the menu bar and the desktop behind them from one sample frame.
(function () {
  const TB = (window.TB = {});
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

  // ---------------------------------------------------------------- shared
  const GLYPH = { up: '●', degraded: '▲', down: '✖', unknown: '○', cached: '◌' };
  const CLS = { up: 'up', degraded: 'warn', down: 'down', unknown: 'unk', cached: 'unk' };
  TB.glyph = (h) => GLYPH[h] || '○';
  TB.cls = (h) => CLS[h] || 'unk';

  function mix(a, b, t) {
    const p = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
    const x = p(a), y = p(b);
    return '#' + x.map((v, i) => Math.round(v + (y[i] - v) * t).toString(16).padStart(2, '0')).join('');
  }
  TB.mix = mix;

  // The TUI's loadColor: teal until the reading nears its limit, amber past it.
  function loadColor(v, limit) {
    if (!(limit > 0) || limit > 100) limit = 100;
    if (v > limit) return '#fbbf24';
    const t = Math.min(1, Math.max(0, (v / limit - 0.55) / 0.45));
    return mix('#5eead4', '#fbbf24', t * t);
  }

  // ----------------------------------------------------------------- icons
  const sv = (body, vb = 20, extra = '') =>
    `<svg viewBox="0 0 ${vb} ${vb}" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" ${extra}>${body}</svg>`;

  function gearPath(cx, cy, ro, ri, n) {
    const pts = [];
    const step = (Math.PI * 2) / n;
    for (let i = 0; i < n; i++) {
      const a = i * step - Math.PI / 2;
      [[-0.5, ri], [-0.3, ri], [-0.2, ro], [0.2, ro], [0.3, ri]].forEach(([f, r]) => {
        pts.push([cx + r * Math.cos(a + f * step), cy + r * Math.sin(a + f * step)]);
      });
    }
    return 'M' + pts.map((p) => p.map((v) => v.toFixed(2)).join(' ')).join('L') + 'Z';
  }

  const I = {
    globe: sv('<circle cx="10" cy="10" r="7.2"/><ellipse cx="10" cy="10" rx="3.1" ry="7.2"/><path d="M2.8 10h14.4"/>'),
    terminal: sv('<rect x="2.6" y="3.6" width="14.8" height="12.8" rx="3.2"/><path d="M6.2 8.1l2.4 1.9-2.4 1.9M10.6 12.3h3.2"/>'),
    gear: sv(`<path d="${gearPath(10, 10, 7.6, 5.9, 8)}"/><circle cx="10" cy="10" r="2.4"/>`),
    scope: sv('<circle cx="10" cy="10" r="7"/><circle cx="10" cy="10" r="3.3"/><circle cx="10" cy="10" r=".7" fill="currentColor"/>'),
    alert: sv('<path d="M8.6 3.9a1.6 1.6 0 0 1 2.8 0l6 10.6a1.6 1.6 0 0 1-1.4 2.4H4a1.6 1.6 0 0 1-1.4-2.4Z"/><path d="M10 8.2v3.4"/><circle cx="10" cy="14" r=".45" fill="currentColor"/>'),
    apps: sv('<path d="M10 2.8 17 6.4 10 10 3 6.4Z"/><path d="M3 10.1l7 3.6 7-3.6"/><path d="M3 13.7l7 3.6 7-3.6"/>'),
    server: sv('<rect x="3" y="3.4" width="14" height="5.6" rx="1.8"/><rect x="3" y="11" width="14" height="5.6" rx="1.8"/><circle cx="6.1" cy="6.2" r=".55" fill="currentColor"/><circle cx="6.1" cy="13.8" r=".55" fill="currentColor"/>'),
    laptop: sv('<rect x="4" y="4.2" width="12" height="8.4" rx="1.4"/><path d="M2.2 15.6h15.6"/>'),
    desktop: sv('<rect x="2.8" y="3.4" width="14.4" height="9.8" rx="1.6"/><path d="M10 13.2v3.2M6.8 16.6h6.4"/>'),
    router: sv('<rect x="2.8" y="10.6" width="14.4" height="5.6" rx="1.8"/><path d="M6.4 13.4h.01M9.2 13.4h.01M10 10.6V7M6.9 5.6a4.4 4.4 0 0 1 6.2 0M5 3.7a7.1 7.1 0 0 1 10 0"/>'),
    edge: sv('<circle cx="10" cy="10" r="7.2"/><ellipse cx="10" cy="10" rx="3.1" ry="7.2"/><path d="M2.8 10h14.4"/>'),
    platform: sv('<path d="M10 2.8 17 6.4 10 10 3 6.4Z"/><path d="M3 10.1l7 3.6 7-3.6"/><path d="M3 13.7l7 3.6 7-3.6"/>'),
    cpu: sv('<rect x="5" y="5" width="10" height="10" rx="2.2"/><rect x="8" y="8" width="4" height="4" rx=".9"/><path d="M8 2.6v2.4M12 2.6v2.4M8 15v2.4M12 15v2.4M2.6 8h2.4M2.6 12h2.4M15 8h2.4M15 12h2.4"/>'),
    memory: sv('<rect x="2.6" y="5.6" width="14.8" height="8" rx="1.8"/><path d="M5.6 13.6v2.6M8.6 13.6v2.6M11.4 13.6v2.6M14.4 13.6v2.6M6 8.6h2.4M11.6 8.6h2.4"/>'),
    drive: sv('<rect x="2.6" y="5.8" width="14.8" height="8.4" rx="2.6"/><path d="M5.8 10h4.4"/><circle cx="14" cy="10" r=".7" fill="currentColor"/>'),
    net: sv('<path d="M6.6 15.4V4.8M3.9 7.5l2.7-2.7 2.7 2.7M13.4 4.6v10.6M10.7 12.5l2.7 2.7 2.7-2.7"/>'),
    power: sv('<path d="M10 3.2v6.4"/><path d="M6.1 5.6a6.1 6.1 0 1 0 7.8 0"/>'),
    chevron: sv('<path d="M8 5.5 12.5 10 8 14.5"/>'),
    download: sv('<path d="M10 3.4v9M6.2 8.8l3.8 3.8 3.8-3.8M4.4 16.2h11.2"/>'),
    bellSlash: sv('<path d="M6.2 6.4a3.9 3.9 0 0 1 7.7.9v2.9l1.6 2.6H8.8M4.6 12.8h1.7l.9-1.5V9.4"/><path d="M8.4 15.3a1.7 1.7 0 0 0 3.2 0"/><path d="M3.6 3.6l12.8 12.8"/>'),
    bolt: sv('<path d="M11 2.8 5.6 11h4l-1 6.2 5.8-8.4h-4.1Z" fill="currentColor" stroke-width="1"/>'),
    info: sv('<circle cx="10" cy="10" r="7.2"/><path d="M10 9v4.6"/><circle cx="10" cy="6.4" r=".5" fill="currentColor"/>'),
    clock: sv('<circle cx="10" cy="10" r="7.2"/><path d="M10 5.8V10l2.8 1.8"/>'),
    fleet: sv('<rect x="3" y="3" width="5.8" height="5.8" rx="1.6"/><rect x="11.2" y="3" width="5.8" height="5.8" rx="1.6"/><rect x="3" y="11.2" width="5.8" height="5.8" rx="1.6"/><rect x="11.2" y="11.2" width="5.8" height="5.8" rx="1.6"/>'),
  };
  TB.icons = I;

  // ------------------------------------------------------------ providers
  // Who runs a node, by any of the names a topology gives it (providers.js).
  // A logo only says who; Native draws it in the text's color, Terminal in
  // the brand's, as the TUI does.
  const norm = (s) => [...String(s || '').toLowerCase()].filter((c) => /[\p{L}\p{N}]/u.test(c)).join('');
  TB.provider = (name) => {
    const n = norm(name);
    if (!n) return null;
    for (const [key, p] of Object.entries(window.TB_PROVIDERS || {})) {
      if (p.names.includes(n) || norm(p.name) === n) return Object.assign({ key }, p);
    }
    return null;
  };
  // A place, such as "homelab", keeps the topology's spelling.
  TB.providerName = (name) => { const p = TB.provider(name); return p && !p.generic ? p.name : name; };
  // The logo fit in a square, its longer side `optical` of it. A glyph is
  // drawn as lines.
  TB.logo = (key, cls = '') => {
    const l = (window.TB_LOGOS || {})[key];
    if (!l) return '';
    const [w, h, k, line, d] = l;
    const paint = line > 0 ? ` fill="none" stroke="currentColor" stroke-width="${line}" stroke-linecap="round" stroke-linejoin="round"` : '';
    return `<svg class="logo ${cls}" viewBox="0 0 1 1"><path transform="translate(${((1 - w * k) / 2).toFixed(4)} ${((1 - h * k) / 2).toFixed(4)}) scale(${k})"${paint} d="${d}"/></svg>`;
  };
  // Where a provider has no logo, or the app doesn't know it, a glyph for
  // its node's kind; nothing where it names none.
  TB.logoKey = (provider, kind) => {
    const p = TB.provider(provider);
    if (p && window.TB_LOGOS[p.key]) return p.key;
    if (!String(provider || '').trim()) return null;
    const k = String(kind || '').toLowerCase();
    return k === 'edge' || k === 'cdn' ? 'glyph.edge' : k === 'platform' || k === 'paas' || k === 'serverless' ? 'glyph.platform' : 'glyph.server';
  };
  const KIND_ICON = { laptop: 'laptop', desktop: 'desktop', router: 'router', edge: 'edge', platform: 'platform' };
  // What stands for a node on its card: its provider's logo, its kind's
  // glyph where there is no logo, or its kind's symbol where it names no
  // provider.
  TB.avatar = (s, icon) => {
    const key = TB.logoKey(s.provider, s.kind);
    let face;
    if (icon) face = icon;
    else if (key) face = TB.logo(key, 'av-logo');
    else face = I[KIND_ICON[s.kind] || 'server'] || I.server;
    return `<span class="nv-ico2">${face}</span>`;
  };
  // The TUI's logo before a name: two cells, in the brand's color 12% toward
  // the text, further while too dark to read on the ink; a glyph is muted.
  TB.tlogo = (provider, p, kind) => {
    const key = TB.logoKey(provider, kind);
    if (!key) return [];
    const k = TB.provider(provider) || {};
    let t = 0.12, c = k.color ? mix(k.color.toLowerCase(), p.text, t) : p.muted;
    const lum = (hex) => {
      const v = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255).map((x) => (x <= 0.03928 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4));
      return 0.2126 * v[0] + 0.7152 * v[1] + 0.0722 * v[2];
    };
    const contrast = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };
    while (k.color && contrast(c, p.ink) < 3 && t < 1) { t += 0.08; c = mix(k.color.toLowerCase(), p.text, Math.min(1, t)); }
    return [{ html: `<span class="tlogo" style="color:${c}">${TB.logo(key)}</span>`, w: 2 }];
  };

  function battery(pct, charging) {
    const w = Math.max(1.5, (10.2 * pct) / 100);
    return sv(`<rect x="2.4" y="6" width="13.6" height="8" rx="2.3"/><path d="M17.9 8.7v2.6"/><rect x="4" y="7.6" width="${w.toFixed(1)}" height="4.8" rx="1.1" fill="currentColor" stroke="none"/>` +
      (charging ? '<path d="M9.9 6.9 7.9 10.3h2.3l-.4 2.8 2.5-3.6h-2.3Z" fill="var(--bolt, #fff)" stroke="none"/>' : ''));
  }

  // A status mark: shape and color both say the health.
  function mark(h, size = 14) {
    const c = `class="mk mk-${TB.cls(h)}" width="${size}" height="${size}"`;
    switch (h) {
      case 'up':
        return `<svg ${c} viewBox="0 0 14 14"><circle cx="7" cy="7" r="5.2" fill="currentColor"/></svg>`;
      case 'degraded':
        return `<svg ${c} viewBox="0 0 14 14"><path d="M6.1 1.9a1 1 0 0 1 1.8 0l5 9.1a1 1 0 0 1-.9 1.5H2a1 1 0 0 1-.9-1.5Z" fill="currentColor"/><path d="M7 5.2v3" stroke="var(--on, #fff)" stroke-width="1.4" stroke-linecap="round"/><circle cx="7" cy="10.2" r=".75" fill="var(--on, #fff)"/></svg>`;
      case 'down':
        return `<svg ${c} viewBox="0 0 14 14"><circle cx="7" cy="7" r="6" fill="currentColor"/><path d="M4.9 4.9l4.2 4.2M9.1 4.9 4.9 9.1" stroke="var(--on, #fff)" stroke-width="1.5" stroke-linecap="round"/></svg>`;
      case 'cached':
        return `<svg ${c} viewBox="0 0 14 14"><circle cx="7" cy="7" r="5" fill="none" stroke="currentColor" stroke-width="1.5" stroke-dasharray="2.2 1.9"/></svg>`;
      default:
        return `<svg ${c} viewBox="0 0 14 14"><circle cx="7" cy="7" r="4.8" fill="none" stroke="currentColor" stroke-width="1.6"/></svg>`;
    }
  }
  TB.mark = mark;

  // The hero's symbol: a flat tile tinted with the verdict's color, edged in
  // it, and its glyph in the color itself.
  function heroSymbol(state) {
    const g = {
      clear: '<path d="M14.5 23.5l6 6 12-13" stroke-width="3.6"/>',
      degraded: '<path d="M23.5 13.5v11" stroke-width="3.8"/><circle cx="23.5" cy="31.6" r="2.3" fill="currentColor" stroke="none"/>',
      incidents: '<path d="M16.5 16.5l14 14M30.5 16.5l-14 14" stroke-width="3.6"/>',
      incomplete: '<circle cx="15.5" cy="23.5" r="2.4" fill="currentColor" stroke="none"/><circle cx="23.5" cy="23.5" r="2.4" fill="currentColor" stroke="none"/><circle cx="31.5" cy="23.5" r="2.4" fill="currentColor" stroke="none"/>',
      offline: '<path d="M13 19.4a15 15 0 0 1 21 0M16.6 23.6a9.6 9.6 0 0 1 13.8 0M20.4 27.6a4.4 4.4 0 0 1 6.2 0" stroke-width="2.6"/><path d="M14 13l19.6 20" stroke-width="2.8"/>',
    }[state];
    return `<div class="nv-sym sym-${state}"><svg viewBox="0 0 47 47" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round">${g}</svg></div>`;
  }

  // Every configured check by health. One tick per check while each can be
  // told apart (an unknown check a hollow tick); past that, runs of color
  // with the unknown hatched. `width` is the bar's width in points.
  function stack(c, width) {
    const n = c.up + c.warn + c.down + c.unknown;
    let fit = null;
    for (const gap of [1.5, 1]) {
      const tick = (width - gap * (n - 1)) / n;
      if (tick >= (gap > 1 ? 2.2 : 1.6)) { fit = gap; break; }
    }
    if (fit) {
      const t = (k, m) => `<i class="t-${k}"></i>`.repeat(m);
      return `<div class="nv-ticks" style="gap:${fit}px">${t('up', c.up)}${t('warn', c.warn)}${t('down', c.down)}${t('unk', c.unknown)}</div>`;
    }
    const seg = (m, k) => (m ? `<i class="seg s-${k}" style="flex:${m}"></i>` : '');
    return `<div class="nv-runs"><div class="nv-stack">${seg(c.up, 'up')}${seg(c.warn, 'warn')}${seg(c.down, 'down')}${seg(c.unknown, 'unk')}</div></div>`;
  }
  // The bar's place while nothing current is known: hatched, as tall as the ticks.
  const stackWithheld = () => '<div class="nv-runs"><div class="nv-stack withheld"></div></div>';

  const SEV = { down: 0, degraded: 1, unknown: 2, cached: 3, up: 4 };
  // Observers in topo's order (PROTOCOL.md §3.3): down, degraded, unknown,
  // up, then by name.
  const worst = (a, b) => SEV[a.health] - SEV[b.health] || a.name.localeCompare(b.name);
  // A title split at its arrows. fitRoutes() cuts it so both ends stay
  // readable, as the app's RouteLayout does.
  const fromArrows = (t) => {
    const parts = t.split(' → ');
    if (parts.length < 2) return esc(t);
    return `<span class="route">${parts.map((x) => `<span class="rp">${esc(x)}</span>`).join('<i class="arr">→</i>')}</span>`;
  };
  // A part that fits an equal share of the room keeps its width, and longer
  // ones split the rest. A cut part ends at a whole letter, and what it
  // leaves goes to the next cut part, shortest first.
  function fitRoutes(root) {
    root.querySelectorAll('.route').forEach((r) => {
      const parts = [...r.children].filter((x) => x.classList.contains('rp'));
      parts.forEach((x) => { x.dataset.full = x.dataset.full || x.textContent; x.textContent = x.dataset.full; });
      const w = (x) => x.getBoundingClientRect().width;
      const ideal = parts.map(w);
      const sum = ideal.reduce((a, b) => a + b, 0);
      let room = r.parentElement.clientWidth - (r.scrollWidth - sum);
      if (sum <= room) return;
      // The text cut to `max`, ending in "…" and never in a space.
      const fit = (x, max) => {
        const chars = [...x.dataset.full];
        let lo = 0, hi = chars.length - 1, best = '…';
        while (lo <= hi) {
          const mid = (lo + hi) >> 1;
          x.textContent = chars.slice(0, mid).join('').replace(/\s+$/, '') + '…';
          if (w(x) <= max) { best = x.textContent; lo = mid + 1; } else hi = mid - 1;
        }
        x.textContent = best;
        return w(x);
      };
      const order = parts.map((_, i) => i).sort((a, b) => ideal[a] - ideal[b]);
      const out = ideal.slice();
      let left = parts.length;
      order.forEach((i) => { out[i] = Math.min(ideal[i], Math.max(0, room) / left); room -= out[i]; left -= 1; });
      order.forEach((i) => {
        if (out[i] >= ideal[i]) return;
        const used = fit(parts[i], out[i]);
        room += out[i] - used;
        out[i] = used;
      });
      order.forEach((i) => {
        if (out[i] >= ideal[i] || room <= 0.5) return;
        const more = Math.min(ideal[i], out[i] + room);
        parts[i].textContent = parts[i].dataset.full;
        const used = more >= ideal[i] ? ideal[i] : fit(parts[i], more);
        room -= used - out[i];
        out[i] = used;
      });
    });
  }
  let fitting = false;
  new MutationObserver(() => {
    if (fitting) return;
    fitting = true;
    requestAnimationFrame(() => { fitting = false; fitRoutes(document); });
  }).observe(document.body, { childList: true, subtree: true });
  const mins = (s) => s.replace(/m$/, ' min').replace(/s ago$/, ' s ago');

  // ---------------------------------------------------------- native theme
  function nvMeter(v, limit, withheld) {
    if (withheld) return '<div class="nv-meter withheld"></div>';
    const over = limit && v > limit;
    return `<div class="nv-meter"><i class="${over ? 'over' : ''}" style="width:${v}%"></i>${limit && limit < 100 ? `<b style="left:${limit}%"></b>` : ''}</div>`;
  }

  // The time where a server is, "9:30 AM", when its place has a zone.
  const localTime = (place) => {
    const z = window.TB_DATA.placeZones[place];
    if (!z) return '';
    const p = zoneParts(z, window.TB_DATA.now);
    return p.time + ' ' + p.period;
  };

  function nvServer(s, opts = {}) {
    const pill = s.withheld ? '<span class="pill p-unk">CACHED</span>'
      : `<span class="pill p-${TB.cls(s.health)}">${s.pill || { up: 'UP', degraded: 'WARN', down: 'DOWN' }[s.health] || 'UNKNOWN'}</span>`;
    const m = (label, r) => `<div class="nv-res"><div class="nv-res-top"><span>${label}</span><b>${!s.withheld && r.v > r.limit ? mark('degraded', 9) : ''}${s.withheld ? '—' : r.v.toFixed(0) + '%'}</b></div>${nvMeter(r.v, r.limit, s.withheld)}</div>`;
    return `<div class="nv-server">
      <div class="nv-server-head">${TB.avatar(s, opts.icon)}
        <div class="nv-server-name"><b>${esc(s.name)}</b><span class="nv-sub"><em>${esc([s.kind, TB.providerName(s.provider)].join(' · '))}</em><i> · ${esc([s.place, localTime(s.place)].filter(Boolean).join(' · '))}</i></span></div>${pill}</div>
      <div class="nv-res3">${m('CPU', s.cpu)}${m('Memory', s.mem)}${m('Disk', s.disk)}</div>
      <div class="nv-server-foot"><span>${esc(s.services)}</span><span>${s.withheld ? 'last reading ' : ''}${esc(s.updated)}</span></div>
    </div>`;
  }

  // A history as bars, newest at the right, over a baseline; before the
  // history is full (60 samples), the left is baseline only.
  function barHistory(vals, top, capacity = 60) {
    const n = Math.max(capacity, vals.length);
    const pitch = 100 / n;
    const bars = vals.slice(-n).map((v, i, a) => {
      const x = 100 - (a.length - i) * pitch;
      return `<i style="left:${x.toFixed(3)}%;width:calc(${pitch.toFixed(3)}% - .6px);height:${Math.max(1, Math.min(1, v / top) * 22).toFixed(2)}px"></i>`;
    }).join('');
    return `<div class="nv-bars">${bars}</div>`;
  }

  // Two histories on one axis: down above the line, up below it, on one scale.
  // Newest at the right, as the CPU's bars: the width holds 60 samples, so
  // before the history is full, the left is the axis alone.
  function mirror(down, up, w = 140, h = 22, capacity = 60) {
    const mid = Math.round(h / 2);
    const peak = Math.max(...down, ...up) * 1.1;
    const pitch = w / (Math.max(2, capacity, down.length, up.length) - 1);
    const area = (vals, sign) => {
      const first = w - (vals.length - 1) * pitch;
      const pts = vals.map((v, i) => [first + i * pitch, mid - sign * Math.min(1, v / peak) * (mid - 1)]);
      const line = pts.map((p, i) => (i ? 'L' : 'M') + p[0].toFixed(1) + ' ' + p[1].toFixed(1)).join('');
      return { line, fill: line + `L${w} ${mid}L${first.toFixed(1)} ${mid}Z` };
    };
    const a = area(down, 1), b = area(up, -1);
    return `<svg class="nv-mirror" viewBox="0 0 ${w} ${h}" preserveAspectRatio="none" width="100%" height="${h}">
      <path d="${a.fill}" fill="var(--acc)" fill-opacity=".26"/><path d="${a.line}" stroke="var(--acc)" stroke-width="1.2" fill="none" vector-effect="non-scaling-stroke" stroke-linejoin="round"/>
      <path d="${b.fill}" fill="var(--acc2)" fill-opacity=".26"/><path d="${b.line}" stroke="var(--acc2)" stroke-width="1.2" fill="none" vector-effect="non-scaling-stroke" stroke-linejoin="round"/>
      <rect x="0" y="${mid - 0.25}" width="${w}" height=".5" fill="var(--sep)"/></svg>`;
  }

  // App, wired and compressed, as Activity Monitor splits "Memory Used".
  function memoryParts(m) {
    const w = (x) => ((x / m.total) * 100).toFixed(3) + '%';
    return `<div class="nv-parts"><i style="width:${w(m.app)}"></i><i style="width:${w(m.wired)}"></i><i style="width:${w(m.comp)}"></i></div>`;
  }

  function nvLocal(L) {
    return `<div class="nv-tiles">
      <div class="nv-tile"><div class="nv-tile-h"><span>${I.cpu}CPU</span><b>${L.cpu.v.toFixed(1)}%</b></div>
        <div class="nv-tile-g">${barHistory(L.cpu.spark, Math.max(25, Math.max(...L.cpu.spark) * 1.2))}</div>
        <div class="nv-tile-f">System ${L.cpu.sys}% · User ${L.cpu.user}%</div></div>
      <div class="nv-tile"><div class="nv-tile-h"><span>${I.memory}Memory</span><b>${L.mem.v.toFixed(1)}%</b></div>
        <div class="nv-tile-bar">${memoryParts(L.mem)}</div>
        <div class="nv-tile-f">Pressure ${L.mem.pressure.toFixed(0)}% · App ${L.mem.app} GB</div></div>
      <div class="nv-tile"><div class="nv-tile-h"><span>${I.drive}Storage</span><b>${L.disk.v.toFixed(1)}%</b></div>
        <div class="nv-tile-bar">${nvMeter(L.disk.v)}</div>
        <div class="nv-tile-f">${L.disk.used} of ${L.disk.total} GB used</div></div>
      <div class="nv-tile"><div class="nv-tile-h"><span>${I.net}Network</span><b class="nv-iface">${L.net.iface}</b></div>
        <div class="nv-tile-g">${mirror(L.net.downSpark, L.net.upSpark)}</div>
        <div class="nv-tile-f"><span class="c-acc">↓</span> ${L.net.down.replace(' kB/s', '')} · <span class="c-acc2">↑</span> ${L.net.up}</div></div>
    </div>
    <div class="nv-batt"><span class="nv-batt-i">${battery(L.battery.v, true)}</span><b>${L.battery.v}%</b><span>${L.battery.state} · ${L.battery.remain}</span></div>`;
  }

  // ------------------------------------------------------------ time zones
  // Listed servers by the zone their place suggests, west to east, and This
  // Mac's own zone marked here. The clock is this Mac's; every mark is topo's.
  function zoneParts(zone, now) {
    const o = {};
    new Intl.DateTimeFormat('en-US', { timeZone: zone, hour: 'numeric', minute: '2-digit', hour12: true, year: 'numeric', month: 'numeric', day: 'numeric', timeZoneName: 'short' })
      .formatToParts(now).forEach((p) => (o[p.type] = p.value));
    const off = new Intl.DateTimeFormat('en-US', { timeZone: zone, timeZoneName: 'longOffset' }).formatToParts(now).find((p) => p.type === 'timeZoneName').value;
    const m = off.match(/GMT([+-])(\d+)(?::(\d+))?/);
    const offset = m ? (m[1] === '-' ? -1 : 1) * (+m[2] * 60 + +(m[3] || 0)) : 0;
    const h24 = new Intl.DateTimeFormat('en-US', { timeZone: zone, hour: 'numeric', minute: 'numeric', hourCycle: 'h23' }).formatToParts(now);
    const hour = +h24.find((p) => p.type === 'hour').value + +h24.find((p) => p.type === 'minute').value / 60;
    return { time: o.hour + ':' + o.minute, period: o.dayPeriod, abbr: o.timeZoneName, offset, hour, day: +o.year * 1e4 + +o.month * 100 + +o.day };
  }
  TB.zones = function (sc) {
    const D = window.TB_DATA;
    const here = zoneParts(D.here, D.now);
    const zones = [];
    let unplaced = 0;
    sc.listed.forEach((s) => {
      const zone = D.placeZones[s.place];
      if (!zone) { unplaced++; return; }
      let z = zones.find((x) => x.zone === zone);
      if (!z) zones.push((z = Object.assign({ zone, places: [], servers: [], here: zone === D.here }, zoneParts(zone, D.now))));
      if (!z.places.includes(s.place)) z.places.push(s.place);
      z.servers.push(s);
    });
    if (!zones.some((z) => z.here)) zones.push(Object.assign({ zone: D.here, places: ['This Mac'], servers: [], here: true }, here));
    zones.sort((a, b) => a.offset - b.offset);
    zones.forEach((z) => {
      const d = (z.offset - here.offset) / 60;
      const hm = Math.abs(d) % 1 ? Math.trunc(Math.abs(d)) + ':' + String(Math.round((Math.abs(d) % 1) * 60)).padStart(2, '0') : String(Math.abs(d));
      z.rel = z.here ? 'here' : (d >= 0 ? '+' : '−') + hm + 'h';
      z.dayNote = z.day > here.day ? 'tomorrow' : z.day < here.day ? 'yesterday' : '';
    });
    return { zones, servers: sc.listed.length, unplaced };
  };

  // How light the local hour is drawn: night from 20:00 to 4:00, day from
  // 8:00 to 16:00, soft between. A clock's hour, not the sun's.
  const daylight = (h) => {
    const t = Math.min(1, Math.max(0, ((1 - Math.cos((2 * Math.PI * h) / 24)) / 2 - 0.25) / 0.5));
    return t * t * (3 - 2 * t);
  };
  // The zone's day from 12 hours before now to 12 hours after, slate around
  // midnight and pale around noon; now is the middle, so every row's now
  // lines up. Neither tone is a status color.
  function ribbon(z, dark) {
    const [night, noon] = dark ? [[107, 125, 184, 0.26], [247, 245, 237, 0.5]] : [[51, 64, 107, 0.44], [61, 61, 77, 0.08]];
    const stops = [];
    for (let i = 0; i <= 48; i++) {
      const b = daylight((((z.hour - 12 + i / 2) % 24) + 24) % 24);
      const c = night.map((n, k) => n + (noon[k] - n) * b);
      stops.push(`rgba(${c.slice(0, 3).map(Math.round).join(',')},${c[3].toFixed(3)}) ${((i / 48) * 100).toFixed(2)}%`);
    }
    let mids = '';
    for (let k = 0; k <= 1; k++) {
      const x = (24 * k - z.hour + 12) / 24;
      if (x > 0 && x < 1) mids += `<i style="left:${(x * 100).toFixed(2)}%"></i>`;
    }
    return `<div class="z-rib"><div class="z-day" style="background:linear-gradient(90deg,${stops.join(',')})">${mids}</div><b></b></div>`;
  }

  // This Mac's location: the system's arrow for "where you are".
  const pin = '<svg viewBox="0 0 20 20" fill="currentColor"><path d="M16.6 3.4 3.6 9.1a.5.5 0 0 0 .1.95l5.6 1.1 1.1 5.6a.5.5 0 0 0 .95.1Z"/></svg>';
  function nvZones(sc, dark) {
    const Z = TB.zones(sc);
    const rows = Z.zones.map((z, i) => {
      const marks = z.servers.slice(0, 8).map((s) => mark(s.health, 8)).join('') + (z.servers.length > 8 ? `<em>+${z.servers.length - 8}</em>` : '');
      const sep = i ? ' z-sep' : '';
      return `<div class="z-t${sep}"><b>${z.time}</b><span>${z.period} · ${z.abbr}</span></div>
        <div class="z-m${sep}"><div class="z-n">${z.here ? `<span class="z-here">${pin}</span>` : ''}<span class="pl">${esc(z.places.join(' · '))}</span><span class="z-marks">${marks}</span></div>${ribbon(z, dark)}</div>
        <div class="z-o${sep}"><b class="${z.here ? 'here' : ''}">${z.rel}</b>${z.dayNote ? `<span>${z.dayNote}</span>` : ''}</div>`;
    }).join('');
    const foot = Z.unplaced ? `<div class="z-foot">${Z.unplaced} without a time zone</div>` : '';
    return `<section class="nv-card"><h3>${I.clock}Time zones<em>${Z.zones.length} zones · ${Z.servers} servers</em></h3><div class="nv-zones">${rows}</div>${foot}</section>`;
  }

  // ---------------------------------------------------------------- fleet
  // Every node topo lists, by who runs it: edges and platforms each on their
  // own, first; then servers by provider, each provider where its first
  // server was. Each node keeps topo's mark; a group has none of its own.
  TB.fleet = function (sc) {
    const edges = [], servers = [];
    sc.listed.forEach((s) => {
      if (s.kind === 'edge' || s.kind === 'platform') {
        edges.push({ title: s.name, provider: s.provider, kind: s.kind, nodes: [s], edge: true });
        return;
      }
      const p = TB.provider(s.provider);
      const key = p ? p.key : norm(s.provider);
      if (!key) { servers.push({ title: s.name, provider: '', kind: s.kind, nodes: [s] }); return; }
      const g = servers.find((x) => x.key === key);
      if (g) g.nodes.push(s);
      else servers.push({ key, title: TB.providerName(s.provider), provider: s.provider, kind: s.kind, nodes: [s] });
    });
    const keys = new Set([...edges, ...servers].filter((g) => g.provider).map((g) => (TB.provider(g.provider) || {}).key || norm(g.provider)));
    return { edges, servers, nodes: sc.listed.length, providers: keys.size, current: sc.verdict.state !== 'offline' };
  };
  // Who runs a group, small: the logo, its kind's glyph, or a lone node's
  // kind.
  function fleetGlyph(g) {
    const key = TB.logoKey(g.provider, g.kind);
    if (key) return `<span class="fl-g">${TB.logo(key)}</span>`;
    return `<span class="fl-g fl-sym">${I[KIND_ICON[g.kind] || 'server'] || I.server}</span>`;
  }
  // The nodes of groups left out for room, trouble first.
  const troubleFirst = (gs) => gs.flatMap((g) => g.nodes).map((s, i) => [s, i])
    .sort((a, b) => SEV[a[0].health] - SEV[b[0].health] || a[1] - b[1]).map((x) => x[0]);
  TB.troubleFirst = troubleFirst;
  // Groups two to a row; groups left out for room, when given, take the
  // next cell with their nodes' marks, trouble first.
  function fleetGrid(F, groups, marks = 6, rest = []) {
    const health = (s) => (F.current ? s.health : 'cached');
    const tail = (nodes) => `<span class="fl-m">${nodes.slice(0, marks).map((s) => mark(health(s), 8)).join('')}${nodes.length > marks ? `<em>+${nodes.length - marks}</em>` : ''}</span>`;
    const cell = (g) => `<div class="fl-c ${F.current ? '' : 'cached'}">${fleetGlyph(g)}<span class="fl-t">${esc(g.title)}</span>${g.edge ? `<em>${esc(g.kind)}</em>` : ''}${tail(g.nodes)}</div>`;
    const more = rest.length ? `<div class="fl-c fl-more ${F.current ? '' : 'cached'}"><span class="fl-g"></span><span class="fl-t">+${rest.length} more</span>${tail(troubleFirst(rest))}</div>` : '';
    return `<div class="fl-grid">${groups.map(cell).join('')}${more}</div>`;
  }
  function nvFleet(sc) {
    const F = TB.fleet(sc);
    return `<section class="nv-card"><h3>${I.fleet}Fleet<em>${F.nodes} servers · ${F.providers} providers</em></h3>${fleetGrid(F, F.edges)}${F.edges.length && F.servers.length ? '<div class="nv-sep fl-sep"></div>' : ''}${fleetGrid(F, F.servers)}</section>`;
  }
  TB._fleet = { nvFleet, fleetGrid };

  // Token sets for the cards renderer, by appearance, as ThemeStore has them.
  // Native is the system's own; Aurora and Linen only set tokens, and Linen
  // its family.
  const TOKENS = {
    aurora: {
      dark: { acc: '#2dd4bf', acc2: '#a78bfa', card: 'rgba(45, 212, 191, .07)', 'card-b': 'rgba(94, 234, 212, .14)', 'panel-bg': 'rgba(12, 28, 34, .62)', fill: 'rgba(94, 234, 212, .2)', fill2: 'rgba(94, 234, 212, .09)' },
      light: { acc: '#0d9488', acc2: '#7c3aed', card: 'rgba(240, 253, 250, .7)', 'card-b': 'rgba(13, 148, 136, .14)', 'panel-bg': 'rgba(236, 253, 248, .62)', fill: 'rgba(13, 148, 136, .18)', fill2: 'rgba(13, 148, 136, .08)' },
    },
    linen: {
      family: "ui-serif, 'New York', Georgia, serif",
      dark: { acc: '#9db0e8', acc2: '#bca7de', card: 'rgba(255, 236, 212, .065)', 'card-b': 'rgba(255, 230, 200, .1)', 'panel-bg': 'rgba(42, 35, 28, .86)', fill: 'rgba(222, 200, 170, .24)', fill2: 'rgba(222, 200, 170, .11)' },
      light: { acc: '#34509a', acc2: '#7a5ba8', card: 'rgba(255, 253, 248, .84)', 'card-b': 'rgba(110, 88, 60, .13)', 'panel-bg': 'rgba(241, 237, 229, .88)', fill: 'rgba(120, 100, 74, .2)', fill2: 'rgba(120, 100, 74, .09)' },
    },
  };
  TB.tokens = TOKENS;
  // The CSS for a token set, and its family; empty for Native.
  const tokenCSS = (o) => {
    const set = o.tokens && TOKENS[o.tokens];
    const t = set && set[o.appearance];
    if (!t) return '';
    return Object.entries(t).map(([k, v]) => `--${k}:${v}`).join(';') + (set.family ? `;font-family:${set.family}` : '') + ';';
  };
  TB.tokenCSS = tokenCSS;
  const tokenStyle = (o) => {
    const css = tokenCSS(o);
    return css ? ` style="${css}"` : '';
  };

  // An alert the menu bar shows in color: degraded or incidents, with status colors on.
  const alertOf = (sc, o) => ['degraded', 'incidents'].includes(sc.verdict.state) && o.color !== 'mono';

  TB._cards = { mark, heroSymbol, stack, stackWithheld, nvMeter, nvServer, nvLocal, fromArrows, mins, worst, I, battery };

  TB.nativePanel = function (sc, o) {
    const L = window.TB_DATA.local;
    const v = sc.verdict;
    const c = sc.counts;
    const total = sc.configured;
    const on = o.sections;
    const out = [];

    if (!o.heroOnly) out.push(`<header class="nv-head">
      <img class="nv-mark" src="assets/mark.svg" alt="">
      <div class="nv-head-t"><b>Topophany</b><span>homelab · all observers</span></div>
      <button class="nv-btn" title="Open in Terminal">${I.terminal}</button>
      <button class="nv-btn" title="Settings">${I.gear}</button>
    </header>`);

    // Status: always first, never optional.
    const leg = (n, h, word) => `<span class="${n ? '' : 'zero'}">${mark(h, 9)}<b>${n}</b>${word}</span>`;
    const offline = v.state === 'offline';
    // While the menu bar shows an alert in color, it can be quieted until it gets worse.
    const quiet = alertOf(sc, o) ? `<button class="nv-quiet${o.quiet ? ' on' : ''}" title="${o.quiet ? 'The menu bar stays quiet until this gets worse. Click to show its colors again.' : 'Quiet the menu bar until this gets worse'}">${I.bellSlash}${o.quiet ? 'Quieted' : 'Quiet'}</button>` : '';
    // With no topo, or one too old, Download gets the latest release.
    const fetching = o.fetch || 'ready';
    const fetch = sc.missing ? `<button class="nv-quiet on" title="Download topo from its latest release on GitHub">${I.download}${fetching === 'downloading' ? 'Downloading 42%' : 'Download topo'}</button>` : '';
    const sub = !sc.missing ? v.sub : { ready: v.sub, downloading: 'Downloading topo 1.3.0 · 42%', failed: 'Couldn’t reach GitHub · try again' }[fetching];
    out.push(`<section class="nv-card nv-hero hero-${v.state}">
      <div class="nv-hero-top">${heroSymbol(v.state)}
        <div class="nv-hero-t"><div class="nv-hero-l"><b>${esc(v.title)}</b>${quiet}${fetch}</div><span>${esc(sub)}</span></div></div>
      ${offline
        ? `<div class="nv-cached"><span class="pill p-unk">CACHED</span>${sc.lastKnown ? `Last snapshot ${esc(sc.updated)} said <b>${esc(sc.lastKnown.toLowerCase())}</b>. ` : ''}Nothing current is known.</div>`
        : `${stack(c, 304)}
      <div class="nv-legend">${leg(c.up, 'up', 'up')}${leg(c.warn, 'degraded', 'warn')}${leg(c.down, 'down', 'down')}${leg(c.unknown, 'unknown', 'unknown')}</div>`}
      <div class="nv-meta"><span>${I.scope}${sc.missing ? 'Observers not known now' : `${sc.observers.live}/${sc.observers.total} observers live`}</span><span>${sc.missing ? '' : offline ? 'Updated ' + esc(sc.updated) : 'Updated ' + esc(sc.updated.replace('s ago', ' s ago'))}</span></div>
    </section>`);

    if (o.heroOnly) return `<div class="nv ${o.appearance}"${tokenStyle(o)}><div class="nv-panel">${out.join('')}</div></div>`;

    if (on.seen) {
      const bad = sc.seen.filter((x) => x.health !== 'up');
      const good = sc.seen.length - bad.length;
      let chips;
      if (offline) chips = `<span class="chip">${mark('cached', 11)}Not known while offline</span>`;
      else if (!bad.length) chips = `<span class="chip chip-calm">${mark('up', 10)}All ${sc.seen.length} observers report no problem</span>`;
      else chips = bad.sort(worst).map((x) => `<span class="chip chip-${TB.cls(x.health)}">${mark(x.health, 11)}${esc(x.name)}<em>${esc(x.note)}</em></span>`).join('') +
        `<span class="chip chip-calm">${mark('up', 10)}${good} others report no problem</span>`;
      out.push(`<section class="nv-card"><h3>${I.scope}Seen from<em>${sc.seen.length} observers</em></h3><div class="nv-chips">${chips}</div></section>`);
    }

    if (on.attention && sc.attention.length) {
      const rows = sc.attention.slice(0, o.limit).map((a) => `<div class="nv-row">
        <span class="nv-row-i">${mark(a.health, 14)}</span>
        <div class="nv-row-m"><div class="t">${fromArrows(a.title)}</div><div class="s">${esc(a.kind)} · from ${esc(a.from)}${a.since ? ' · ' + mins(a.since) : ''}</div></div>
        <span class="pill plain p-${TB.cls(a.health)}">${esc(a.state.toUpperCase())}</span></div>`).join('');
      const rest = sc.attention.length - o.limit + sc.more;
      out.push(`<section class="nv-card"><h3>${I.alert}Needs attention<em>${sc.attention.length + sc.more}</em></h3>${rows}
        ${rest > 0 ? `<a class="nv-more">${rest} more in Topophany ${I.chevron}</a>` : ''}</section>`);
    }

    if (on.map && TB.nvMap && !sc.missing) out.push(TB.nvMap(sc, o));

    if (on.apps) {
      const rows = sc.apps.map((a) => {
        const h = a.cached ? 'cached' : a.health || 'up';
        const dots = a.services.map((s) => mark(a.cached ? 'cached' : s, 8)).join('');
        return `<div class="nv-app ${a.cached ? 'cached' : ''}"><span class="nv-app-n">${mark(h, 10)}${esc(a.name)}</span><span class="nv-dots">${dots}</span><span class="nv-app-note ${a.health === 'degraded' ? 'attn' : ''}">${esc(a.note || 'all up')}</span></div>`;
      }).join('');
      out.push(`<section class="nv-card"><h3>${I.apps}Applications<em>23 services in 6</em></h3>${rows}</section>`);
    }

    if (on.fleet) out.push(nvFleet(sc));

    if (on.servers) {
      out.push(`<section class="nv-card"><h3>${I.server}Servers<em>2 pinned</em></h3>${sc.servers.map((s) => nvServer(s)).join('<div class="nv-sep"></div>')}</section>`);
    }

    if (on.zones) out.push(nvZones(sc, o.appearance === 'dark'));

    if (on.mac && o.mac !== 'off') {
      if (o.mac === 'server') {
        const ob = sc.mac.observes;
        out.push(`<section class="nv-card"><h3>${I.laptop}This Mac<em>as a server · macbook</em></h3>${nvServer(sc.mac, { icon: I.laptop })}
          <div class="nv-observes">${I.scope}<span>Observes from here</span><b>${mark(ob.health, 10)}${esc(ob.text)}</b></div></section>`);
      } else {
        out.push(`<section class="nv-card"><h3>${I.laptop}This Mac<em>${L.model} · local readings</em></h3>${nvLocal(L)}</section>`);
      }
    }

    out.push(`<footer class="nv-foot"><span class="nv-conn ${sc.live ? 'live' : 'off'}"><i></i>${sc.live ? 'Connected · ' + sc.collector : 'Unreachable · ' + sc.collector}</span><button>Quit</button></footer>`);
    return `<div class="nv ${o.appearance}"${tokenStyle(o)}><div class="nv-panel">${out.join('')}</div></div>`;
  };

  // ------------------------------------------------------- cells renderer
  // The Terminal theme, and any theme built on it: a monospace cell grid
  // whose sections are the TUI's boxed panels, the title set in the border.
  // A theme of this family is only a palette; the layout is the renderer's.
  const PALETTES = {
    terminal: {
      ink: '#0a1016', inkHi: '#0f1820', sel: '#112c34', key: '#1a2b36', line: '#243443', track: '#16232d',
      text: '#d5dee7', muted: '#8393a3', faint: '#4a5868', glow: '#f0fdfa', acc: '#5eead4', acc2: '#7dd3fc', kind: '#fda4af',
      up: '#4ade80', warn: '#fbbf24', down: '#f87171', unk: '#6b7a8c',
    },
    // The same renderer, a light palette.
    paper: {
      ink: '#f5f0e6', inkHi: '#ece5d7', sel: '#e4ddcc', key: '#e3dbca', line: '#d3c9b5', track: '#e6dfd0',
      text: '#2a2925', muted: '#6e695d', faint: '#a29c8e', glow: '#ffffff', acc: '#0f766e', acc2: '#1d4ed8', kind: '#be185d',
      up: '#15803d', warn: '#b8720a', down: '#b91c1c', unk: '#87929b',
    },
    // Pastels on deep indigo.
    dusk: {
      ink: '#1a1735', inkHi: '#201c3f', sel: '#2e2959', key: '#2a2650', line: '#3d3869', track: '#252147',
      text: '#e6e2f8', muted: '#a49ecb', faint: '#68629a', glow: '#fff4fa', acc: '#b4a7fa', acc2: '#8bd3f7', kind: '#f4a7c9',
      up: '#6ee7b0', warn: '#f7b96b', down: '#f7768e', unk: '#7a759f',
    },
  };
  TB.palettes = PALETTES;
  const pal = (o) => PALETTES[(o && o.palette) || 'terminal'];
  const paletteVars = (p) => Object.entries({
    ink: p.ink, 'ink-hi': p.inkHi, sel: p.sel, key: p.key, line: p.line, track: p.track, text: p.text, muted: p.muted, glow: p.glow,
    faint: p.faint, acc: p.acc, acc2: p.acc2, kind: p.kind, up: p.up, warn: p.warn, down: p.down, unk: p.unk,
  }).map(([k, v]) => `--${k}:${v}`).join(';');
  TB.paletteVars = paletteVars;

  // One cell per code point; anything a fallback font might draw wider is
  // held to one cell. Box drawing and blocks stay in the monospace font.
  const cell = (ch) => {
    const cp = ch.codePointAt(0);
    if (cp < 0x80 || (cp >= 0x2500 && cp <= 0x259f)) return esc(ch);
    return `<span class="g">${esc(ch)}</span>`;
  };
  const len = (s) => [...s].length;
  const trunc = (s, n) => (len(s) > n ? [...s].slice(0, Math.max(0, n - 1)).join('').replace(/\s+$/, '') + '…' : s);
  // A route in n cells, cut as the app cuts it so both ends stay readable.
  const troute = (parts, n) => {
    const whole = parts.join(' → ');
    let room = n - 3 * (parts.length - 1);
    if (len(whole) <= n || parts.length < 2 || room < 3 * parts.length) return trunc(whole, n);
    const out = parts.slice();
    let left = parts.length;
    parts.map((_, i) => i).sort((a, b) => len(parts[a]) - len(parts[b])).forEach((i) => {
      out[i] = trunc(parts[i], Math.floor(room / left));
      room -= len(out[i]);
      left -= 1;
    });
    return out.join(' → ');
  };
  const S = (text, cls) => ({ text, cls });
  const draw = (segs) => segs.map((s) => (s.html ? s.html : `<span class="${s.cls || ''}">${[...s.text].map(cell).join('')}</span>`)).join('');
  const width = (segs) => segs.reduce((n, s) => n + (s.w != null ? s.w : len(s.text)), 0);
  function tl(left, right = [], cls = '', w = IW) {
    const pad = Math.max(1, w - width(left) - width(right));
    return `<div class="tl ${cls}">${draw(left)}${' '.repeat(pad)}${draw(right)}</div>`;
  }
  const blank = () => '<div class="tl"> </div>';
  const tglyph = (h) => S(TB.glyph(h), 'h-' + TB.cls(h));
  const W = 48;   // the panel's columns inside its margins
  const IW = 46;  // a box's columns inside its border

  function box(title, right, body, opt = {}) {
    const style = opt.tint ? ` style="--bc:${opt.tint}"` : '';
    return `<section class="tbox ${opt.cls || ''}"${style}><div class="tbox-t"><span>${draw(title)}</span>${right ? `<span>${draw(right)}</span>` : ''}</div>${body}</section>`;
  }
  const title = (t, extra) => [S(' ' + t, 'acc b'), ...(extra ? [S(' · ', 'faint'), S(extra, 'muted')] : []), S(' ')];

  const BIG = {
    '0': ['###', '#.#', '#.#', '#.#', '###'], '1': ['.#.', '##.', '.#.', '.#.', '###'],
    '2': ['###', '..#', '###', '#..', '###'], '3': ['###', '..#', '.##', '..#', '###'],
    '4': ['#.#', '#.#', '###', '..#', '..#'], '5': ['###', '#..', '###', '..#', '###'],
    '6': ['###', '#..', '###', '#.#', '###'], '7': ['###', '..#', '.#.', '.#.', '.#.'],
    '8': ['###', '#.#', '###', '#.#', '###'], '9': ['###', '#.#', '###', '..#', '###'],
    '-': ['...', '...', '###', '...', '...'],
  };
  // The TUI's bigText: a 3x5 pixel font in half blocks, each pixel row a
  // shade of the color, lit from above.
  function bigDigits(s, color, p) {
    const shade = [mix(color, p.glow, 0.4), mix(color, p.glow, 0.18), color, mix(color, p.ink, 0.14), mix(color, p.ink, 0.28)];
    const wcols = 4 * s.length - 1;
    let rects = '';
    [...s].forEach((ch, k) => BIG[ch].forEach((row, y) => [...row].forEach((px, x) => {
      if (px === '#') rects += `<rect x="${x + 4 * k}" y="${y}" width="1.04" height="1.04" fill="${shade[y]}"/>`;
    })));
    return `<svg class="tbig" style="width:${wcols}ch" viewBox="0 0 ${wcols} 6" preserveAspectRatio="none" shape-rendering="crispEdges">${rects}</svg>`;
  }
  const tone = (cls, p) => ({ up: p.up, warn: p.warn, down: p.down, unk: p.unk }[cls]);

  // The TUI's loadColor over the palette: accent until a reading nears its
  // limit, warning past it.
  function loadTone(v, limit, p) {
    if (!(limit > 0) || limit > 100) limit = 100;
    if (v > limit) return p.warn;
    const t = Math.min(1, Math.max(0, (v / limit - 0.55) / 0.45));
    return mix(p.acc, p.warn, t * t);
  }
  function tBar(v, limit, n, p, opt = {}) {
    if (opt.withheld) return { html: `<span class="tbar withheld" style="width:${n}ch"></span>`, w: n };
    const color = opt.plain ? p.acc : loadTone(v, limit, p);
    const lim = limit && limit < 100 ? `<b style="left:${limit}%"></b>` : '';
    return { html: `<span class="tbar" style="width:${n}ch"><i style="width:${v}%;--c:${color}"></i>${lim}</span>`, w: n };
  }
  // The TUI's sparks: one block per reading, scaled to the series' peak.
  const sparks = (vals, n, top) => vals.slice(-n).map((v) => '▁▂▃▄▅▆▇█'[Math.max(0, Math.min(7, Math.round((v / top) * 7)))]).join('');

  function tStatusBody(sc, p, w, opt = {}) {
    const v = sc.verdict;
    const c = sc.counts;
    const offline = v.state === 'offline';
    const vcls = offline ? 'unk' : TB.cls(v.health);
    const out = [];
    out.push(tl([S((offline ? '◌' : TB.glyph(v.health)) + ' ' + (opt.short ? v.tui.replace('INCOMPLETE EVIDENCE', 'INCOMPLETE') : v.tui), 'h-' + vcls + ' b')], [], '', w));
    const big = bigDigits(v.big, tone(vcls, p), p);
    const lines = opt.short ? [v.bigTop.split(' ')[0], v.bigTop.split(' ').slice(1).join(' ')] : [v.bigTop, v.bigBottom];
    out.push(`<div class="tblock"><span class="tb-sp"> </span>${big}<span class="tb-sp">  </span><div class="tb-lines"><div class="tl">${draw([S(lines[0])])}</div><div class="tl">${draw([S(lines[1], 'muted')])}</div><div class="tl"> </div></div></div>`);
    if (offline) {
      out.push(tl([S('╌'.repeat(w), 'faint')], [], '', w));
      out.push(sc.lastKnown ? tl([S('◌', 'h-unk'), S(opt.short ? ' last: ' : ' last snapshot said ', 'muted'), S(sc.lastKnown.toLowerCase(), 'b')], [], '', w)
        : tl([S('◌', 'h-unk'), S(' nothing current is known', 'muted')], [], '', w));
    } else {
      const share = (n) => Math.round((n / sc.configured) * w);
      const rule = [S('━'.repeat(share(c.up)), 'h-up'), S('━'.repeat(share(c.warn)), 'h-warn'), S('━'.repeat(share(c.down)), 'h-down'), S('━'.repeat(share(c.unknown)), 'h-unk')];
      rule[0].text = '━'.repeat(Math.max(0, len(rule[0].text) + w - width(rule)));
      out.push(tl(rule, [], '', w));
      const cnt = (n, h, word) => [S(TB.glyph(h), n ? 'h-' + TB.cls(h) : 'faint'), S(' '), S(String(n), n ? 'b' : 'faint'), S(word ? ' ' + word + '  ' : ' ', n ? 'muted' : 'faint')];
      if (opt.short) out.push(tl([...cnt(c.up, 'up'), ...cnt(c.warn, 'degraded'), ...cnt(c.down, 'down'), ...cnt(c.unknown, 'unknown')], [], '', w));
      else out.push(tl([...cnt(c.up, 'up', 'up'), ...cnt(c.warn, 'degraded', 'warn'), ...cnt(c.down, 'down', 'down'), ...cnt(c.unknown, 'unknown', 'unknown')], [], '', w));
    }
    if (!opt.short) {
      out.push(tl([S('⚑', sc.incidents ? 'h-down' : 'faint'), S(' '), S(String(sc.incidents), sc.incidents ? 'b' : 'faint'), S(' incidents', 'muted')],
        [S('◎', 'acc2'), S(' '), S(sc.observers.live + '/' + sc.observers.total, 'b'), S(' observers live', 'muted')], '', w));
    }
    return out.join('');
  }
  const statusTint = (sc, p) => mix(tone(sc.verdict.state === 'offline' ? 'unk' : TB.cls(sc.verdict.health), p), p.ink, 0.42);

  function tSeenBody(sc, w, max = 99) {
    const bad = sc.seen.filter((x) => x.health !== 'up').sort(worst);
    if (sc.verdict.state === 'offline') return tl([S('◌', 'h-unk'), S(' not known while offline', 'muted')], [], '', w);
    if (!bad.length) return tl([tglyph('up'), S(' all ' + sc.seen.length + ' observers report no problem', 'muted')], [], '', w);
    return bad.slice(0, max).map((x) => tl([tglyph(x.health), S(' '), S(trunc(x.name, w - 10))], [S(x.note, 'h-' + TB.cls(x.health))], '', w)).join('') +
      tl([tglyph('up'), S(' ' + (sc.seen.length - bad.length) + ' others report no problem', 'muted')], [], '', w);
  }

  function tAttentionBody(sc, w, limit, opt = {}) {
    const rows = sc.attention.slice(0, limit).map((a, i) => {
      const st = a.state;
      const head = tl([tglyph(a.health), S(' '), S(troute(a.title.split(' → '), w - 3 - len(st) - 1), 'b')], [S(st, 'h-' + TB.cls(a.health) + ' b')], '', w);
      const sub = tl([S('  ' + [a.kind, a.from, a.since].filter(Boolean).join(' · '), 'muted')], [], '', w);
      return `<div class="trow ${i === 0 && opt.focus ? 'focus' : ''}">${head}${opt.compact ? '' : sub}</div>`;
    }).join('');
    const rest = sc.attention.length - limit + sc.more;
    return rows + (rest > 0 ? tl([S('+' + rest + ' more', 'faint')], opt.compact ? [] : [S('↵', 'acc'), S(' open in topo', 'faint')], '', w) : '');
  }

  function tAppsBody(sc, w, opt = {}) {
    return sc.apps.map((a) => {
      const h = a.cached ? 'cached' : a.health || 'up';
      const dots = [];
      a.services.forEach((s) => dots.push(a.cached ? S('◌', 'h-unk') : tglyph(s), ...(opt.tight ? [] : [S(' ')])));
      const note = a.tuiNote && !opt.noNote ? S(a.tuiNote, a.health === 'degraded' ? 'h-warn' : 'muted') : S('');
      return tl([tglyph(h), S(' '), S(trunc(a.name, opt.name || 15).padEnd(opt.name || 15), a.health === 'degraded' ? 'b' : ''), S(' '), ...dots], [note], '', w);
    }).join('');
  }

  function tServerBody(s, p, w, opt = {}) {
    const out = [];
    // What fits beside the age: the provider goes first; the kind and the
    // time where it is stay.
    const age = s.withheld ? 'last ' + s.updated : s.updated;
    const t = opt.clock ? localTime(s.place) : '';
    const head = (provider) => [S(s.kind, 'kind'), ...(provider ? [S(' · ', 'faint'), S(provider, 'muted')] : []), S(' · ', 'faint'), S(s.place, 'muted'),
      ...(t ? [S(' · ', 'faint'), S(t)] : [])];
    let first = head(TB.providerName(s.provider));
    if (width(first) > w - len(age) - 1) first = head('');
    out.push(tl(first, [S(age, 'faint')], '', w));
    const barN = opt.bar || 20;
    const row = (label, r) => {
      const val = s.withheld ? '     —' : (r.v.toFixed(1) + '%').padStart(6);
      const detail = opt.noDetail || s.withheld ? '' : r.detail.replace(' / ', '/');
      return tl([S(label.padEnd(opt.label || 7), 'muted'), S(val, s.withheld ? 'faint' : 'b'), S(' '), tBar(r.v, r.limit, barN, p, { withheld: s.withheld })], [S(detail, 'muted')], '', w);
    };
    out.push(row('CPU', s.cpu), row(opt.label === 4 ? 'MEM' : 'MEMORY', s.mem), row('DISK', s.disk));
    if (s.observes && opt.observes) {
      const ob = s.observes;
      out.push(tl([S('◎', 'acc2'), S(' from here  ', 'muted'), tglyph(ob.health), S(' ' + ob.text, ob.health === 'up' ? '' : 'h-' + TB.cls(ob.health))], [S(ob.ago, 'faint')], '', w));
    }
    return out.join('');
  }
  const serverTitle = (s, p) => [S(' '), S(TB.glyph(s.withheld ? 'cached' : s.health), 'h-' + (s.withheld ? 'unk' : TB.cls(s.health))), S(' '),
    ...TB.tlogo(s.provider, p || PALETTES.terminal, s.kind), S(s.name + ' ', 'b')];
  const serverPill = (s) => {
    const t = s.withheld ? 'CACHED' : s.pill || { up: 'UP', degraded: 'WARN', down: 'DOWN' }[s.health] || 'UNKNOWN';
    return [S(' ' + t + ' ', 'pill pill-' + (s.withheld ? 'unk' : TB.cls(s.health)))];
  };

  // Time zones as the TUI would draw them: two lines a zone, the ribbon one
  // cell per 24/n hours in the palette's own tones, now the middle cell.
  const isDark = (p) => parseInt(p.ink.slice(1, 3), 16) < 128;
  function tRibbon(z, n, p) {
    const [night, day] = isDark(p) ? [p.track, p.muted] : [p.faint, p.track];
    const stops = [];
    for (let i = 0; i < n; i++) {
      const c = mix(night, day, daylight((((z.hour - 12 + ((i + 0.5) / n) * 24) % 24) + 24) % 24));
      stops.push(`${c} ${((i / n) * 100).toFixed(3)}% ${(((i + 1) / n) * 100).toFixed(3)}%`);
    }
    let mids = '';
    for (let k = 0; k <= 1; k++) {
      const x = (24 * k - z.hour + 12) / 24;
      if (x > 0 && x < 1) mids += `<i style="left:${(x * 100).toFixed(2)}%"></i>`;
    }
    return { html: `<span class="trib" style="width:${n}ch;background:linear-gradient(90deg,${stops.join(',')})">${mids}<b></b></span>`, w: n };
  }
  function tZonesBody(sc, p, w) {
    const Z = TB.zones(sc);
    const tw = Math.max(...Z.zones.map((z) => Math.max(len(z.time + ' ' + z.period), Math.min(len(z.abbr), 9))));
    const rw = Math.max(...Z.zones.map((z) => Math.max(len(z.rel), len(z.dayNote))));
    const ribbonW = w - tw - 2 - 1 - rw;
    const out = [];
    Z.zones.forEach((z) => {
      const marks = [];
      z.servers.slice(0, 8).forEach((s) => marks.push(tglyph(s.health)));
      if (z.servers.length > 8) marks.push(S('+' + (z.servers.length - 8), 'faint'));
      const room = w - tw - 2 - marks.length - 1 - rw - 1;
      out.push(tl([S((z.time + ' ' + z.period).padEnd(tw), 'b'), S('  '), S(trunc(z.places.join(' · '), room))],
        [...marks, S(' '), S(z.rel.padStart(rw), z.here ? 'acc' : 'muted')], '', w));
      out.push(tl([S(trunc(z.abbr, tw).padEnd(tw), 'faint'), S('  '), tRibbon(z, ribbonW, p)], [S(z.dayNote.padStart(rw), 'faint')], '', w));
    });
    if (Z.unplaced) out.push(tl([S(Z.unplaced + ' without a time zone', 'faint')], [], '', w));
    return { body: out.join(''), zones: Z.zones.length, servers: Z.servers };
  }

  // Fleet as the TUI would draw it: two to a line, logo, who, and a mark per
  // node at the column's end; servers start a line of their own.
  // At most `lines` lines: groups left out are counted in the last cell,
  // their nodes' marks kept.
  function tFleetBody(sc, p, w, marks = 4, lines = Infinity) {
    const F = TB.fleet(sc);
    const gap = 2;
    const cw = Math.floor((w - gap) / 2);
    const entry = (lead, title, cls, tag, nodes) => {
      const tail = nodes.slice(0, marks).map((s) => tglyph(F.current ? s.health : 'cached'));
      if (nodes.length > marks) tail.push(S('+' + (nodes.length - marks), 'faint'));
      const room = cw - 2 - width(tail) - 1;
      const segs = [...lead, S(trunc(title, Math.max(1, room)), cls)];
      if (tag && len(title) + len(tag) <= room) segs.push(S(tag, 'faint'));
      return [...segs, S(' '.repeat(Math.max(1, cw - width(segs) - width(tail)))), ...tail];
    };
    const group = (g) => {
      const logo = TB.tlogo(g.provider, p, g.kind);
      return entry(logo.length ? logo : [S('  ')], g.title, '', g.edge ? ' ' + g.kind : '', g.nodes);
    };
    const all = F.edges.length + F.servers.length;
    const rows = (n) => Math.ceil(n / 2);
    const need = (k) => { const e = Math.min(k, F.edges.length); return rows(e) + rows(k - e + (k < all ? 1 : 0)); };
    let shown = all;
    while (shown > 0 && need(shown) > lines) shown -= 1;
    const edges = F.edges.slice(0, shown);
    const servers = F.servers.slice(0, shown - edges.length).map(group);
    const rest = [...F.edges.slice(edges.length), ...F.servers.slice(shown - edges.length)];
    if (rest.length) servers.push(entry([S('  ')], '+' + rest.length + ' more', 'muted', '', TB.troubleFirst(rest)));
    const out = [];
    [edges.map(group), servers].forEach((part) => {
      for (let i = 0; i < part.length; i += 2) {
        const segs = part[i].slice();
        if (part[i + 1]) segs.push(S(' '.repeat(gap)), ...part[i + 1]);
        out.push(tl(segs, [], '', w));
      }
    });
    return { body: out.join(''), nodes: F.nodes, providers: F.providers };
  }

  TB.tuiPanel = function (sc, o) {
    const p = pal(o);
    const L = window.TB_DATA.local;
    const v = sc.verdict;
    const offline = v.state === 'offline';
    const out = [];

    out.push(tl([S('◉', 'acc'), S(' TOPOPHANY', 'acc b'), S(' ╱ ', 'faint'), S('homelab', 'b'), S(' · all observers', 'faint')],
      [sc.live ? S('● LIVE', 'h-up b') : S('◌ OFFLINE', 'h-down b')], 'bar head', W));

    // `m` quiets the menu bar's alert, or shows it again.
    const quietKey = ['degraded', 'incidents'].includes(v.state) && o.color !== 'mono'
      ? '<div class="tgap4"></div>' + tl([S(' m ', 'key'), S(o.quiet ? ' menu bar quiet until it gets worse · undo' : ' quiet the menu bar until it gets worse', 'muted')], [], '', IW) + '<div class="tgap4"></div>' : '';
    // `d` downloads topo when there's none, or it's too old.
    const fetchWords = { ready: ' download topo from its latest release', downloading: ' downloading topo 1.3.0 · 42%', failed: ' couldn’t reach GitHub · try again' }[o.fetch || 'ready'];
    const fetchKey = sc.missing ? '<div class="tgap4"></div>' + tl([S(' d ', 'key'), S(fetchWords, 'muted')], [], '', IW) + '<div class="tgap4"></div>' : '';
    const age = offline ? (sc.updated ? 'cached ' + sc.updated : 'cached') : 'updated ' + sc.updated;
    out.push(box(title('STATUS'), [S(' ' + age + ' ', 'muted')], tStatusBody(sc, p, IW) + quietKey + fetchKey, { tint: statusTint(sc, p), cls: 'status' }));
    if (o.heroOnly) return `<div class="tv" style="${paletteVars(p)}"><div class="tv-panel">${out.join('')}<div class="tgap"></div></div></div>`;

    if (o.sections.seen) out.push(box(title('SEEN FROM', String(sc.seen.length)), null, tSeenBody(sc, IW)));
    if (o.sections.attention && sc.attention.length) {
      out.push(box(title('NEEDS ATTENTION', String(sc.attention.length + sc.more)), null, tAttentionBody(sc, IW, o.limit, { focus: true })));
    }
    if (o.sections.map && TB.tvMap && !sc.missing) out.push(TB.tvMap(sc, o, TB._cells));
    if (o.sections.apps) out.push(box(title('SERVICES', '23 in 6 apps'), null, tAppsBody(sc, IW)));
    if (o.sections.fleet) {
      const f = tFleetBody(sc, p, IW);
      out.push(box(title('FLEET', String(f.nodes)), [S(' ' + f.providers + ' providers ', 'muted')], f.body));
    }
    if (o.sections.servers) sc.servers.forEach((s) => out.push(box(serverTitle(s, p), serverPill(s), tServerBody(s, p, IW, { clock: true }))));
    if (o.sections.zones) {
      const z = tZonesBody(sc, p, IW);
      out.push(box(title('TIME ZONES', String(z.zones)), [S(' ' + z.servers + ' servers ', 'muted')], z.body));
    }

    if (o.sections.mac && o.mac !== 'off') {
      if (o.mac === 'server') {
        const s = sc.mac;
        out.push(box([...title('THIS MAC'), S(TB.glyph(s.withheld ? 'cached' : s.health), 'h-' + (s.withheld ? 'unk' : TB.cls(s.health))), S(' ' + s.name + ' ', 'b')], serverPill(s), tServerBody(s, p, IW, { observes: true, clock: true })));
      } else {
        const lab = (t) => S(t.padEnd(7), 'muted');
        const n = 19;
        const body = [
          tl([lab('CPU'), S((L.cpu.v.toFixed(1) + '%').padStart(6), 'b'), S(' '), S(sparks(L.cpu.spark, n, Math.max(...L.cpu.spark)), 'acc')], [S('sys ' + Math.round(L.cpu.sys) + ' usr ' + Math.round(L.cpu.user), 'muted')]),
          tl([lab('MEMORY'), S((L.mem.v.toFixed(1) + '%').padStart(6), 'b'), S(' '), tBar(L.mem.v, 0, n, p, { plain: true })], [S('press ' + L.mem.pressure.toFixed(0) + '%', 'muted')]),
          tl([lab('DISK'), S((L.disk.v.toFixed(1) + '%').padStart(6), 'b'), S(' '), tBar(L.disk.v, 0, n, p, { plain: true })], [S(Math.round(L.disk.used) + '/' + Math.round(L.disk.total) + ' GB', 'muted')]),
          tl([lab('NET'), S('↓ ', 'acc'), S(L.net.down, 'b'), S('  ↑ ', 'acc2'), S(L.net.up, 'b')], [S(L.net.iface, 'muted')]),
          tl([lab('POWER'), S(L.battery.v + '%', 'b'), S(' ' + L.battery.state.toLowerCase(), 'h-up'), S(' · ' + L.battery.remain, 'muted')]),
        ].join('');
        out.push(box(title('THIS MAC', 'local readings'), [S(' ' + L.model + ' ', 'muted')], body));
      }
    }

    const key = (k, label) => [S(' ' + k + ' ', 'key'), S(' ' + label + '  ', 'muted')];
    out.push('<div class="tgap"></div>' + tl([...key('↵', 'Open'), ...key(',', 'Settings'), ...key('q', 'Quit')],
      [S(sc.collector + ' · ' + (sc.live ? sc.updated.replace(' ago', '') : 'unreachable'), sc.live ? 'faint' : 'h-down')], 'bar foot', W));
    return `<div class="tv" style="${paletteVars(p)}"><div class="tv-panel">${out.join('')}</div></div>`;
  };

  // Shared with the widgets, which draw the same sections at other sizes.
  TB._cells = { S, tl, draw, box, title, trunc, tglyph, bigDigits, tBar, sparks, pal, paletteVars, statusTint, tone,
    tStatusBody, tSeenBody, tAttentionBody, tAppsBody, tServerBody, serverTitle, serverPill, tZonesBody, tFleetBody };

  // -------------------------------------------------------- status item
  // The globe's meridians at `turn`, in meridians from the still pose:
  // front halves of ellipses, fading toward the rim. Seven go round, so at
  // rest two stand either side of the middle.
  TB.meridians = function (turn) {
    const step = 2 * Math.PI / 7;
    let out = '';
    for (let k = 0; k < 7; k++) {
      const lon = (turn + 0.5 + k) * step;
      let t = Math.min(1, Math.max(0, (Math.cos(lon) - 0.5) / 0.4));
      t = t * t * (3 - 2 * t);
      if (t < 0.004) continue;
      const rx = 7 * Math.sin(lon);
      out += `<path d="M9 2A${Math.abs(rx).toFixed(3)} 7 0 0 ${rx >= 0 ? 1 : 0} 9 16" opacity="${t.toFixed(3)}"/>`;
    }
    return out;
  };

  // "343.9 kB/s" in the menu bar's room: "344 kB/s"; "1.4M" in a chip's.
  const shortRate = (s, chip) => {
    const m = /([\d.]+)\s*([kMG]?)B\/s/.exec(s || '');
    if (!m) return '–';
    const v = +m[1];
    const n = v >= 100 ? String(Math.round(v)) : String(+v.toFixed(1));
    return chip ? n + (m[2] ? m[2].toUpperCase() : 'B') : n + ' ' + m[2] + 'B/s';
  };

  // This Mac's readings before the globe, in the menu bar's ink.
  function nativeReadings(kinds) {
    const L = window.TB_DATA.local;
    const value = (v) => `<span class="rv"><b>100%</b><i>${v}</i></span>`;
    const parts = kinds.map((k) => {
      if (k === 'cpu') {
        const h = L.cpu.spark.slice(-10);
        const bars = h.map((v, i) => {
          const bh = Math.max(1.5, Math.min(1, v / 100) * 11.5);
          const age = (h.length - 1 - i) / 9;
          return `<rect x="${((10 - h.length + i) * 2.4).toFixed(1)}" y="${(11.5 - bh).toFixed(2)}" width="1.5" height="${bh.toFixed(2)}" rx=".75" opacity="${(1 - 0.6 * age).toFixed(2)}"/>`;
        }).join('');
        return `<span class="nr nr-cpu"><svg viewBox="0 0 23.1 11.5" width="23.1" height="11.5" fill="currentColor">${bars}</svg>${value(Math.round(L.cpu.v) + '%')}</span>`;
      }
      if (k === 'memory') {
        const c = 2 * Math.PI * 5.25;
        return `<span class="nr"><svg viewBox="0 0 12.5 12.5" width="12.5" height="12.5" fill="none" stroke="currentColor" stroke-width="2"><circle cx="6.25" cy="6.25" r="5.25" stroke-opacity=".26"/><circle cx="6.25" cy="6.25" r="5.25" stroke-linecap="round" stroke-dasharray="${(c * L.mem.v / 100).toFixed(2)} ${c.toFixed(2)}" transform="rotate(-90 6.25 6.25)"/></svg>${value(Math.round(L.mem.v) + '%')}</span>`;
      }
      return `<span class="nr nr-net"><span class="nn"><b>88.8 MB/s</b><i>${shortRate(L.net.up)}<br>${shortRate(L.net.down)}</i></span><span class="na">↑<br>↓</span></span>`;
    });
    return `<span class="nreads">${parts.join('')}</span>`;
  }

  // The same, as the TUI writes them, in a chip of their own.
  function tuiReadings(kinds) {
    const L = window.TB_DATA.local;
    const parts = kinds.map((k) => {
      if (k === 'cpu') return `<span class="m">CPU </span><span class="acc">${sparks(L.cpu.spark, 6, 100)}</span> ${(Math.round(L.cpu.v) + '%').padEnd(4)}`;
      if (k === 'memory') return `<span class="m">MEM </span><span class="tbar" style="width:3ch"><i style="width:${L.mem.v}%;--c:var(--acc)"></i></span> ${(Math.round(L.mem.v) + '%').padEnd(4)}`;
      return `<span class="acc">↓</span>${shortRate(L.net.down, true).padEnd(5)}<span class="acc2"> ↑</span>${shortRate(L.net.up, true).padEnd(5)}`;
    });
    return `<span class="tchip reads">${parts.join('  ')}</span>`;
  }

  // The globe with a status badge cut into its corner, after this Mac's
  // readings when shown. `turn` turns the globe; `motion` lets the page's
  // animator turn it while what it shows is current.
  TB.statusItem = function (sc, o) {
    const v = sc.verdict;
    const st = v.state === 'offline' ? 'cached' : v.health;
    const live = v.state !== 'offline' && o.motion !== false;
    const reads = o.readings || [];
    if (o.theme === 'tui') {
      const g = v.state === 'offline' ? '◌' : TB.glyph(v.health);
      const cls = v.state === 'offline' ? 'unk' : o.quiet && ['degraded', 'down'].includes(v.health) ? 'quiet' : TB.cls(v.health);
      const text = o.text === 'symbol' ? '' : o.text === 'count'
        ? (v.count ? ' ' + v.count : '') : ' ' + v.tui.replace('INCOMPLETE EVIDENCE', 'INCOMPLETE');
      const vars = TB.paletteVars(TB.palettes[o.palette || 'terminal']);
      const chip = `<span class="tchip"><span class="g h-${cls}${live ? ' breathe' : ''}" data-g="${g}">${g}</span>${esc(text)}</span>`;
      return `<span class="mb-item ours titem ${o.pressed ? 'pressed' : ''}" style="${vars}">${reads.length ? tuiReadings(reads) : ''}${chip}</span>`;
    }
    // Quieted, an alert's badge keeps its shape in the menu bar's ink.
    const mono = o.color === 'mono' || (o.quiet && (st === 'degraded' || st === 'down'));
    const id = 'm' + Math.random().toString(36).slice(2, 8);
    const badge = {
      up: '<circle cx="14.6" cy="14.6" r="3.3" fill="var(--b)"/>',
      degraded: '<path d="M14.6 10.9l3.7 6.5h-7.4Z" fill="var(--b)" stroke="var(--b)" stroke-width=".8" stroke-linejoin="round"/>',
      down: '<rect x="11.1" y="11.1" width="7" height="7" rx="1.6" fill="var(--b)"/><path d="M13.1 13.1l3 3M16.1 13.1l-3 3" stroke="var(--bx)" stroke-width="1.15" stroke-linecap="round"/>',
      unknown: '<circle cx="14.6" cy="14.6" r="2.7" fill="none" stroke="var(--b)" stroke-width="1.3"/>',
      cached: '<circle cx="14.6" cy="14.6" r="2.7" fill="none" stroke="var(--b)" stroke-width="1.3" stroke-dasharray="1.3 1.123"/>',
    }[st];
    const words = { clear: 'All clear', degraded: 'Degraded', incidents: v.count + ' incidents', incomplete: 'Incomplete', offline: 'Offline' }[v.state];
    const text = o.text === 'symbol' ? '' : o.text === 'count' ? (v.count ? String(v.count) : '') : words;
    return `<span class="mb-item ours nitem b-${mono ? 'mono' : TB.cls(st)} ${o.pressed ? 'pressed' : ''}">${reads.length ? nativeReadings(reads) : ''}
      <svg viewBox="0 0 19 19" width="19" height="19"${live ? ' data-live="1"' : ''}><defs><mask id="${id}"><rect width="19" height="19" fill="#fff"/><circle cx="14.6" cy="14.6" r="5.1" fill="#000"/></mask></defs>
        <g mask="url(#${id})" fill="none" stroke="currentColor" stroke-width="1.45" stroke-linecap="round"><circle cx="9" cy="9" r="7"/><path d="M2 9h14"/><g class="mer">${TB.meridians(o.turn || 0)}</g></g>${badge}</svg>${text ? `<span class="nitem-t">${esc(text)}</span>` : ''}</span>`;
  };

  // Turns every globe under `root` that's live, a meridian every 2.4 s, as
  // the app does; nothing moves when the reader asks for reduced motion.
  TB.animate = function (root) {
    if (window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    const frame = (ms) => {
      const turn = ms / 1000 / 2.4;
      root.querySelectorAll('svg[data-live] g.mer').forEach((g) => { g.innerHTML = TB.meridians(turn); });
      requestAnimationFrame(frame);
    };
    requestAnimationFrame(frame);
  };

  // ----------------------------------------------------------- menu bar
  const wifi = '<svg viewBox="0 0 20 16" width="17" height="14" fill="currentColor"><path d="M10 13.6a1.5 1.5 0 1 0 0 .01ZM5.9 9.7a5.9 5.9 0 0 1 8.2 0l-1.3 1.4a4 4 0 0 0-5.6 0ZM3 6.8a10 10 0 0 1 14 0l-1.4 1.4a8 8 0 0 0-11.2 0ZM.2 3.9a14 14 0 0 1 19.6 0l-1.4 1.4A12 12 0 0 0 1.6 5.3Z"/></svg>';
  const cc = '<svg viewBox="0 0 20 16" width="17" height="14" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="1.5" y="1.5" width="17" height="5.4" rx="2.7"/><rect x="1.5" y="9.1" width="17" height="5.4" rx="2.7"/><circle cx="6" cy="4.2" r="1.3" fill="currentColor"/><circle cx="14" cy="11.8" r="1.3" fill="currentColor"/></svg>';
  const batt = '<svg viewBox="0 0 28 14" width="26" height="13"><rect x=".75" y=".75" width="23.5" height="12.5" rx="3.6" fill="none" stroke="currentColor" stroke-opacity=".45" stroke-width="1.2"/><rect x="2.5" y="2.5" width="16.5" height="9" rx="2.1" fill="currentColor"/><path d="M26 5v4" stroke="currentColor" stroke-opacity=".45" stroke-width="1.6" stroke-linecap="round"/></svg>';
  const search = '<svg viewBox="0 0 16 16" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"><circle cx="6.8" cy="6.8" r="5"/><path d="M10.6 10.6 14.5 14.5"/></svg>';

  TB.menubar = function (appearance, item, opts = {}) {
    return `<div class="mb mb-${appearance}">
      <div class="mb-left"><span class="mb-apple"><svg viewBox="0 0 24 24" width="14" height="16" fill="currentColor"><path d="M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.546 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zM15.53 3.83c.843-1.012 1.4-2.427 1.245-3.83-1.207.052-2.662.805-3.532 1.818-.78.896-1.454 2.338-1.273 3.714 1.338.104 2.715-.688 3.559-1.701"/></svg></span><b>Finder</b><span>File</span><span>Edit</span><span>View</span><span>Go</span><span>Window</span><span>Help</span></div>
      <div class="mb-right">${item}<span class="mb-sys">${wifi}</span><span class="mb-sys">${batt}</span><span class="mb-sys">${search}</span><span class="mb-sys">${cc}</span><span class="mb-clock">${opts.clock || 'Sun Oct 18&nbsp;&nbsp;6:30 AM'}</span></div>
    </div>`;
  };

  // A desktop with the menu bar and, if asked, the panel open beneath it.
  TB.scene = function (el, sc, o) {
    const item = TB.statusItem(sc, Object.assign({}, o, { pressed: o.open !== false }));
    const panel = o.open === false ? '' : (o.theme === 'tui' ? TB.tuiPanel(sc, o) : TB.nativePanel(sc, o));
    el.className = `desk wall-${o.appearance} ${o.cls || ''}`;
    el.innerHTML = TB.menubar(o.appearance, item) + (panel ? `<div class="drop">${panel}</div>` : '');
    if (panel) {
      requestAnimationFrame(() => {
        const d = el.querySelector('.drop');
        const it = el.querySelector('.mb-item.ours');
        const er = el.getBoundingClientRect();
        const ir = it.getBoundingClientRect();
        const dw = d.offsetWidth;
        let left = ir.left - er.left + ir.width / 2 - dw / 2;
        left = Math.max(10, Math.min(left, er.width - dw - 10));
        d.style.left = left + 'px';
        d.style.visibility = 'visible';
        if (o.fit) el.style.height = d.offsetHeight + 31 + (o.fitPad || 34) + 'px';
      });
    }
  };

  TB.defaults = () => ({
    theme: 'native', appearance: 'dark', text: 'count', color: 'status', mac: 'local', limit: 3,
    sections: { seen: true, attention: true, map: true, apps: true, fleet: true, servers: false, zones: true, mac: true },
    mapMode: 'geo', mapFrame: 'fit',
  });
})();
