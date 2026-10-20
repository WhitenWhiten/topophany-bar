// Service cards in topophany-bar: the pinned Services section of the panel
// and the Service widget, in both renderers, from `service.card` rows. Built
// from the same pieces as the Server card and widget (render.js, widgets.js),
// so a service and a server read as one family.
(function () {
  const TB = window.TB;
  const C = TB._cards;
  const T = TB._cells;
  const S = T.S;
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const len = (s) => [...String(s)].length;

  // ------------------------------------------------------------ the row
  // What topo sends as `service.card`'s seen_from: the service's checks by
  // observer, worst first, each observer labelled by its place, or its
  // name where two share a place. (topo builds this; the app only shows it.)
  const SEV = { down: 0, degraded: 1, unknown: 2, up: 3 };
  function seenFrom(c) {
    const by = new Map();
    c.vantages.forEach((v) => {
      if (!by.has(v.observer.id)) by.set(v.observer.id, { observer: v.observer, place: v.place, checks: [] });
      by.get(v.observer.id).checks.push(v);
    });
    const out = [...by.values()];
    out.forEach((o) => o.checks.sort((a, b) => SEV[a.health] - SEV[b.health]));
    out.forEach((o) => {
      o.label = out.filter((x) => x.place === o.place).length > 1 ? o.observer.name.replace(o.place, '').trim() : o.place;
      o.worst = o.checks[0];
    });
    return out.sort((a, b) => SEV[a.worst.health] - SEV[b.worst.health]);
  }
  TB.seenFrom = seenFrom;

  const PILL = { up: 'UP', degraded: 'WARN', down: 'DOWN' };
  const pillWord = (c, o = {}) => (o.stale || c.note === 'cached' ? 'CACHED' : c.note === 'affected' ? 'AFFECTED' : PILL[c.health] || 'UNKNOWN');
  const pillCls = (c, o = {}) => (o.stale || c.note === 'cached' ? 'unk' : c.note === 'affected' ? 'warn' : TB.cls(c.health));
  const markOf = (c, o = {}) => (o.stale || c.note === 'cached' ? 'cached' : c.note === 'affected' && c.health === 'up' ? 'degraded' : c.health);
  const ms = (v) => (v == null ? '—' : v + ' ms');
  const pct = (v) => (v == null ? '—' : (v >= 99.95 ? '100' : v.toFixed(1)) + '%');
  const fresh = (v, o) => !o.stale && v.freshness === 'fresh';
  const colos = (c) => [...new Set(c.vantages.map((v) => v.colo).filter(Boolean))];
  const edge = (c) => c.endpoints.flatMap((e) => e.via)[0] || (['edge', 'platform'].includes(c.host.kind) ? c.host : null);
  // The node a service runs on, as the server cards' avatar takes it.
  const hostNode = (c) => ({ provider: c.host.provider, kind: c.host.kind, name: c.host.name });
  const logoOf = (ref, cls = 'sv-logo') => {
    const key = ref && TB.logoKey(ref.provider, ref.kind);
    return key ? TB.logo(key, cls) : '';
  };
  const where = (c) => [c.application.name, 'on ' + c.host.name].filter(Boolean).join(' · ');

  // ------------------------------------------------------- cards renderer
  // Recent samples as a chart on one baseline: a passing sample rises as
  // tall as it took, against the slowest shown, at half strength; a failing
  // one hangs below the line in its color, so trouble differs in place as
  // well as color. No sample, no mark. Newest at the right.
  function nvSpark(slots, n, w, h = 18, withheld) {
    if (withheld) return `<span class="sv-spark withheld" style="height:${h}px"></span>`;
    const shown = slots.slice(-n);
    const base = Math.round(h * 0.68);
    const pitch = w / n;
    const bw = Math.max(1, pitch - (pitch > 3 ? 1 : 0.6));
    const slowest = Math.max(1, ...shown.filter((s) => s[0] === 'ok').map((s) => s[1]));
    let r = '';
    shown.forEach(([o, v], i) => {
      const x = (w - (shown.length - i) * pitch).toFixed(2);
      if (o === 'ok') {
        const bh = Math.max(1.5, (v / slowest) * (base - 1));
        r += `<rect class="ok" x="${x}" y="${(base - bh).toFixed(2)}" width="${bw.toFixed(2)}" height="${bh.toFixed(2)}" rx=".6"/>`;
      } else if (o !== 'none') {
        const cls = o === 'fail' ? 'down' : o === 'policy' ? 'warn' : 'unk';
        r += `<rect class="${cls}" x="${x}" y="${base + 1.5}" width="${bw.toFixed(2)}" height="${(h - base - 1.5).toFixed(2)}" rx=".6"/>`;
      }
    });
    return `<svg class="sv-spark" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}"><line x1="0" x2="${w}" y1="${base + 0.5}" y2="${base + 0.5}"/>${r}</svg>`;
  }

  // One row per observer: a mark per check, its place, the worst check's
  // recent samples, its median over the day and the day's share up.
  function nvRows(c, o, opt) {
    const rows = seenFrom(c).slice(0, opt.rows || 3);
    if (!rows.length) return `<div class="sv-quiet">${C.mark('unknown', 10)}<span>Not monitored<em>no check measures it</em></span></div>`;
    return rows.map((r) => {
      const v = r.worst;
      const marks = r.checks.slice(0, 3).map((x) => C.mark(o.stale ? 'cached' : x.health, opt.mark || 10)).join('');
      return `<div class="sv-row ${opt.cls || ''}"><span class="sv-marks">${marks}</span><span class="sv-place">${esc(r.label)}</span>${nvSpark(v.slots, opt.n || 30, opt.sw || 120, opt.sh || 18, o.stale)}<b>${fresh(v, o) && v.latency ? (opt.unit === false ? v.latency.p50_ms + '<small>ms</small>' : ms(v.latency.p50_ms)) : '—'}</b>${opt.noUp ? '' : `<i>${o.stale ? '—' : pct(v.up_24h)}</i>`}</div>`;
    }).join('');
  }
  const nvPill = (c, o) => `<span class="pill p-${pillCls(c, o)}">${pillWord(c, o)}</span>`;

  // In the panel: the card for each pinned service.
  function nvService(c, o = {}) {
    const checks = c.vantages.length;
    const failing = c.vantages.filter((v) => v.health === 'down').length;
    const said = !checks ? 'not monitored' : (checks === 1 ? '1 check' : checks + ' checks') + (failing ? ` · ${failing} failing` : ' · all passing');
    const codes = colos(c), e = edge(c);
    const via = e ? `<span class="sv-via">${logoOf(e)}${esc(codes.length ? codes.join(' · ') : e.name)}</span>` : '';
    return `<div class="nv-server sv">
      <div class="nv-server-head">${TB.avatar(hostNode(c))}
        <div class="nv-server-name"><b>${esc(c.name)}</b><span class="nv-sub"><em>${esc(where(c))}</em></span></div>${nvPill(c, o)}</div>
      <div class="sv-head"><span>Seen from</span><span><em>p50</em><em>24h</em></span></div>
      <div class="sv-rows">${nvRows(c, o, { n: 34, sw: 136 })}</div>
      <div class="nv-server-foot"><span>${esc(said)}</span><span class="sv-foot-r">${via}${esc(o.age || '4s ago')}</span></div>
    </div>`;
  }
  TB.nvService = nvService;

  // ------------------------------------------------------- cells renderer
  // Recent samples as the TUI draws them on a card: a passing one a block
  // as tall as it took, any other its strip glyph, on the track.
  function tSpark(slots, n, withheld) {
    if (withheld) return { html: `<span class="tbar withheld" style="width:${n}ch"></span>`, w: n };
    const shown = slots.slice(-n);
    const slowest = Math.max(1, ...shown.filter((s) => s[0] === 'ok').map((s) => s[1]));
    let html = '<span class="tspark">' + '<i> </i>'.repeat(n - shown.length);
    shown.forEach(([o, v]) => {
      if (o === 'ok') html += `<i class="ok">${'▁▂▃▄▅▆▇'[Math.max(0, Math.min(6, Math.round((v / slowest) * 6)))]}</i>`;
      else if (o === 'none') html += '<i class="faint">·</i>';
      else html += `<i class="${o === 'fail' ? 'h-down' : o === 'policy' ? 'h-warn' : 'h-unk'}"><span class="g">${o === 'fail' ? '✖' : o === 'policy' ? '▲' : '○'}</span></i>`;
    });
    return { html: html + '</span>', w: n };
  }
  const tTitle = (c, p, o = {}) => [S(' '), S(TB.glyph(markOf(c, o)), 'h-' + TB.cls(markOf(c, o))), S(' '), S(c.name + ' ', 'b')];
  const tPill = (c, o = {}) => [S(' ' + pillWord(c, o) + ' ', 'pill pill-' + pillCls(c, o))];
  function tServiceBody(c, p, w, o = {}) {
    const out = [];
    const age = o.stale ? 'last ' + (o.age || '47 min ago') : o.age || '4s';
    const logo = TB.tlogo(c.host.provider, p, c.host.kind);
    out.push(T.tl([S('on ', 'faint'), ...logo, S(T.trunc(c.host.name, w - 20), 'kind'), ...(c.application.name ? [S(' · ', 'faint'), S(c.application.name, 'muted')] : [])], [S(age, 'faint')], '', w));
    const rows = seenFrom(c).slice(0, 3);
    if (!rows.length) out.push(T.tl([S('◌', 'faint'), S(' not monitored', 'muted'), S(' · no check measures it', 'faint')], [], '', w));
    const M = Math.max(1, ...rows.map((r) => Math.min(3, r.checks.length)));
    const P = 9, N = 6, U = 5;
    const n = w - (M + 1 + P + 1 + 1 + N + 2 + U);
    rows.forEach((r) => {
      const v = r.worst;
      const marks = r.checks.slice(0, M).map((x) => (o.stale ? S('◌', 'h-unk') : T.tglyph(x.health)));
      out.push(T.tl([...marks, S(' '.repeat(M - marks.length + 1)), S(T.trunc(r.label, P).padEnd(P)), S(' '), tSpark(v.slots, n, o.stale), S(' '),
        S((fresh(v, o) && v.latency ? ms(v.latency.p50_ms) : '—').padStart(N), fresh(v, o) ? '' : 'faint'), S('  '), S((o.stale ? '—' : pct(v.up_24h)).padStart(U), 'muted')], [], '', w));
    });
    if (o.foot !== false) {
      const left = c.depends_on.length
        ? [S('→ ', 'acc'), ...c.depends_on.slice(0, 2).flatMap((d, i) => [...(i ? [S('  ')] : []), T.tglyph(d.affected && d.health === 'up' ? 'degraded' : d.health), S(' ' + T.trunc(d.name, 14))])]
        : [S(c.used_by.length ? 'used by ' + c.used_by.length : 'depends on nothing', 'faint')];
      const e = edge(c), codes = colos(c);
      const right = e ? [S('⇠ ', 'muted'), ...TB.tlogo(e.provider, p, e.kind), S(codes.length ? codes.join(' · ') : e.name, 'muted')] : [S(c.vantages.length + (c.vantages.length === 1 ? ' check' : ' checks'), 'faint')];
      out.push(T.tl(left, right, '', w));
    }
    return out.join('');
  }
  TB.tService = (c, p, w, o) => T.box(tTitle(c, p, o), tPill(c, o), tServiceBody(c, p, w, o));

  // ----------------------------------------------------- the panel section
  // Services (pinned) sits after Applications: an application's row says
  // its services in a dot each, and a pinned one opens up below.
  const pulse = '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M2.6 10.4h3.1l1.9-4.2 3.1 8.6 2.3-6.1 1.4 1.7h3"/></svg>';
  TB.icons = Object.assign(TB.icons || {}, { pulse });
  const wrapNative = TB.nativePanel, wrapTui = TB.tuiPanel;
  TB.nativePanel = function (sc, o) {
    const html = wrapNative(sc, o);
    if (!o.services || !o.services.length) return html;
    const section = `<section class="nv-card"><h3>${pulse}Services<em>${o.services.length} pinned</em></h3>${o.services.map((c) => nvService(c, o)).join('<div class="nv-sep"></div>')}</section>`;
    const at = ['Fleet<em>', 'Servers<em>', 'Time zones<em>', 'This Mac<em>'].map((k) => html.indexOf(k)).filter((i) => i >= 0).sort((a, b) => a - b)[0];
    const start = at == null ? html.indexOf('<footer class="nv-foot">') : html.lastIndexOf('<section class="nv-card">', at);
    return html.slice(0, start) + section + html.slice(start);
  };
  TB.tuiPanel = function (sc, o) {
    const html = wrapTui(sc, o);
    if (!o.services || !o.services.length) return html;
    const p = T.pal(o);
    const boxes = o.services.map((c) => TB.tService(c, p, 46, o)).join('');
    const at = ['>FLEET<', '>TIME ZONES<', '>THIS MAC<'].map((k) => html.indexOf(k.slice(1, -1))).filter((i) => i >= 0).sort((a, b) => a - b)[0];
    if (at == null) return html.replace('<div class="tgap"></div>', boxes + '<div class="tgap"></div>');
    const start = html.lastIndexOf('<section class="tbox', at);
    return html.slice(0, start) + boxes + html.slice(start);
  };

  // ------------------------------------------------------------ widgets
  const SIZE = TB.widgetSize;
  function nativeWidget(size, c, o) {
    const head = `<div class="w-srv-top">${TB.avatar(hostNode(c))}<div class="nv-server-name"><b>${esc(c.name)}</b><span>on ${esc(c.host.name)}</span></div></div>`;
    const age = o.stale ? `last ${o.age || '47 min ago'}` : o.age || '4s ago';
    const left = `<div class="w-col">${head}<div class="sv-wrows">${nvRows(c, o, { n: 14, sw: 40, sh: 16, noUp: true, mark: 9, cls: 'w', unit: false })}</div><div class="w-foot">${nvPill(c, o)}<span>${esc(age)}</span></div></div>`;
    let body = left;
    if (size === 'm') {
      const eps = c.endpoints.slice(0, 1).map((e) => {
        const via = e.via[0];
        const host = e.address.replace(/^[a-z]+:\/\//, '').replace(/\/.*$/, '');
        return `<div class="w-app">${C.mark(o.stale ? 'cached' : e.health || 'unknown', 9)}<span>${esc(host)}</span>${via ? `<em class="sv-via">${logoOf(via)}</em>` : `<em>${esc(e.network)}</em>`}</div>`;
      }).join('');
      const h = c.host;
      const runs = `<div class="w-app">${C.mark(o.stale ? 'cached' : h.health, 9)}<span>${esc(h.name)}</span><em>${esc(h.kind)}</em></div>`;
      const deps = c.depends_on.slice(0, 1).map((d) => `<div class="w-app">${C.mark(o.stale ? 'cached' : d.affected && d.health === 'up' ? 'degraded' : d.health, 9)}<span>${esc(d.name)}</span><em>needs</em></div>`).join('');
      const e = edge(c), codes = colos(c);
      const marks = c.vantages.map((v) => v.health).sort((a, b) => SEV[a] - SEV[b]).map((hh) => C.mark(o.stale ? 'cached' : hh, 9)).join('');
      const foot = e && codes.length
        ? `<div class="w-obs">${logoOf(e)}<span>Answered from</span><b>${esc(o.stale ? 'not known' : codes.join(' · '))}</b></div>`
        : `<div class="w-obs">${C.I.scope}<span>Checks</span><b class="sv-marks">${marks || '<em>none</em>'}</b></div>`;
      body = `<div class="w-split"><div class="w-col w-left">${left}</div><div class="w-col w-right"><h4>Reached at<em>${c.endpoints.length}</em></h4>${eps}<h4 class="w-gap2">Runs on</h4>${runs}${deps}${foot}</div></div>`;
    }
    return `<div class="wdg nv ${o.appearance} wd-${size} ${o.mode || ''}" style="${TB.tokenCSS(o)}width:${SIZE[size][0]}px;height:${SIZE[size][1]}px">${body}</div>`;
  }
  // The cells renderer's widgets fill their box as the Status widget does:
  // the small one gives each observer two lines, its latency over its
  // samples; the medium one adds a line for what it depends on and where
  // the edge answered, and one for the address it is known by.
  function terminalWidget(size, c, o) {
    const p = T.pal(o);
    const cols = { s: 22, m: 51 }[size];
    const w = cols - 2;
    const age = o.stale ? 'last' : (o.age || '4s ago').replace(' ago', '');
    const rows = seenFrom(c).slice(0, 3);
    let body;
    if (size === 's') {
      const name = T.tl([S(TB.glyph(markOf(c, o)), 'h-' + TB.cls(markOf(c, o))), S(' ' + T.trunc(c.name, cols - 3 - len(age)), 'b')], [S(age, 'faint')], 'whead', cols);
      let lines = rows.map((r) => {
        const v = r.worst;
        const marks = r.checks.slice(0, 2).map((x) => (o.stale ? S('◌', 'h-unk') : T.tglyph(x.health)));
        const value = S(fresh(v, o) && v.latency ? ms(v.latency.p50_ms) : '—', fresh(v, o) ? '' : 'faint');
        return T.tl([...marks, S(' ' + T.trunc(r.label, w - 8 - marks.length))], [value], '', w) +
          T.tl([S('  '), tSpark(v.slots, w - 2, o.stale)], [], '', w);
      }).join('');
      if (!rows.length) lines = T.tl([S('◌', 'faint'), S(' not monitored', 'muted')], [], '', w) + T.tl([S(T.trunc('  no check measures it', w), 'faint')], [], '', w);
      const used = Math.max(1, rows.length) * 2;
      const host = T.tl([S('on ', 'faint'), ...TB.tlogo(c.host.provider, p, c.host.kind), S(T.trunc(c.host.name, w - 5), 'kind')], [], '', w);
      const fill = used <= 4 ? '<div class="tl"> </div>'.repeat(5 - used) + host : '';
      body = name + T.box(rows.length ? [S(' SEEN FROM', 'acc b'), S(' ' + rows.length + ' ', 'muted')] : [S(' SERVICE ', 'acc b')], tPill(c, o), lines + fill);
    } else {
      const head = T.tl([S('◉', 'acc'), S(' homelab', 'b')], [o.stale ? S('◌', 'h-unk b') : S('● LIVE', 'h-up b')], 'whead', cols);
      const ep = c.endpoints.find((e) => e.network === 'public') || c.endpoints[0];
      const known = ep
        ? T.tl([S(ep.network.padEnd(9), ep.network === 'public' ? 'acc2' : 'muted'), S(T.trunc(ep.address, w - 12))], [o.stale ? S('◌', 'h-unk') : ep.health ? T.tglyph(ep.health) : S('·', 'faint')], '', w)
        : T.tl([S('no endpoint declared', 'faint')], [], '', w);
      body = head + T.box(tTitle(c, p, o), tPill(c, o), tServiceBody(c, p, w, o) + known);
    }
    return `<div class="wdg tv wd-${size} ${o.mode || ''}" style="${T.paletteVars(p)};width:${SIZE[size][0]}px;height:${SIZE[size][1]}px">${body}</div>`;
  }
  TB.serviceWidget = (size, c, o) => (o.theme === 'tui' ? terminalWidget : nativeWidget)(size, c, o);
})();
