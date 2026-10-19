// Topophany Bar design preview: widgets. Each widget is built from the same
// section pieces as the menu bar panel, in the same theme, so a widget on the
// desktop and the panel under the menu bar read as one thing.
(function () {
  const TB = window.TB;
  const C = TB._cards;
  const T = TB._cells;
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

  // Widget sizes in points, on a 170 pt grid with 24 pt gaps.
  const SIZE = { s: [170, 170], m: [364, 170], l: [364, 364], xl: [752, 364] };
  // Columns of 11 pt SF Mono that fit each size inside its margins.
  const COLS = { s: 22, m: 51, l: 51, xl: 108 };

  // ------------------------------------------------------------- native
  const legend = (c) => {
    const leg = (n, h, word) => `<span class="${n ? '' : 'zero'}">${C.mark(h, 9)}<b>${n}</b>${word}</span>`;
    return `<div class="nv-legend">${leg(c.up, 'up', 'up')}${leg(c.warn, 'degraded', 'warn')}${leg(c.down, 'down', 'down')}${leg(c.unknown, 'unknown', 'unknown')}</div>`;
  };
  const offline = (sc) => sc.verdict.state === 'offline';
  const foot = (sc, wide) => `<div class="w-foot"><span>${C.I.scope}${sc.observers.live}/${sc.observers.total}${wide ? ' observers live' : ''}</span><span>${esc(sc.age)}</span></div>`;

  // The status bar's width in each layout: the widget's, the left column's.
  const BAR = { s: 142, m: 136, l: 336, xl: 350 };

  // In a narrow column the bar's ticks wrap into a grid: every check as its
  // mark, a column at a time in the bar's order, so trouble gathers at the
  // right. Past what can be read, the stacked bar.
  function checkGrid(c, width, height = 34) {
    const n = c.up + c.warn + c.down + c.unknown;
    const gap = 1.5;
    let g = null;
    for (let rows = 1; rows <= Math.min(8, n); rows++) {
      const cols = Math.ceil(n / rows);
      const w = (width - gap * (cols - 1)) / cols;
      const side = Math.min(w, 7.5, (height - gap * (rows - 1)) / rows);
      if (side < 3.5 || (rows > 1 && w > 1.5 * side) || side <= (g ? g.side : 0) + 0.01) continue;
      g = { rows, cols, w, side };
    }
    if (!g) return C.stack(c, width);
    const marks = [...Array(c.up).fill('up'), ...Array(c.warn).fill('degraded'), ...Array(c.down).fill('down'), ...Array(c.unknown).fill('unknown')];
    const svgs = marks.map((h, k) => {
      const x = Math.floor(k / g.rows) * (g.w + gap) + (g.w - g.side) / 2;
      const y = (k % g.rows) * (g.side + gap);
      return C.mark(h, g.side.toFixed(2)).replace('<svg ', `<svg x="${x.toFixed(2)}" y="${y.toFixed(2)}" `);
    }).join('');
    const W = (g.cols * g.w + (g.cols - 1) * gap).toFixed(2);
    const H = (g.rows * g.side + (g.rows - 1) * gap).toFixed(2);
    return `<div class="w-checks"><svg width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">${svgs}</svg></div>`;
  }

  function nStatusBlock(sc, big, size) {
    const checks = offline(sc) ? C.stackWithheld() : big ? C.stack(sc.counts, BAR[size]) : checkGrid(sc.counts, BAR[size]);
    return `<div class="w-status ${big ? 'big' : ''}">
      <div class="w-top">${C.heroSymbol(sc.verdict.state)}${big ? `<div class="w-title"><b>${esc(sc.verdict.title)}</b><span>${esc(sc.verdict.sub)}</span></div>` : ''}<img class="w-mark" src="assets/mark.svg" alt=""></div>
      ${big ? '' : `<div class="w-title"><b>${esc(sc.verdict.title.replace('Evidence incomplete', 'Incomplete'))}</b><span>${esc(sc.short)}</span></div>`}
      ${checks}
      ${big && !offline(sc) ? legend(sc.counts) : ''}
    </div>`;
  }
  function nAttention(sc, n) {
    return `<h4>${C.I.alert}Needs attention<em>${sc.attention.length + sc.more}</em></h4>` + sc.attention.slice(0, n).map((a) =>
      `<div class="w-row">${C.mark(a.health, 12)}<div><div class="t">${C.fromArrows(a.title)}</div><div class="s">${esc(a.from)} · ${C.mins(a.since)}</div></div></div>`).join('');
  }
  function nApps(sc, n = 6) {
    return `<h4>${C.I.apps}Applications<em>${sc.apps.length}</em></h4>` + sc.apps.slice(0, n).map((a) =>
      `<div class="w-app ${a.cached ? 'cached' : ''}">${C.mark(a.cached ? 'cached' : a.health || 'up', 9)}<span>${esc(a.name)}</span><i>${a.services.map((x) => C.mark(a.cached ? 'cached' : x, 7)).join('')}</i></div>`).join('');
  }
  function nSeen(sc) {
    const bad = sc.seen.filter((x) => x.health !== 'up').sort(C.worst);
    let chips;
    if (offline(sc)) chips = `<span class="chip">${C.mark('cached', 10)}Not known now</span>`;
    else if (!bad.length) chips = `<span class="chip chip-calm">${C.mark('up', 9)}All ${sc.seen.length} report no problem</span>`;
    else chips = bad.slice(0, 2).map((x) => `<span class="chip chip-${TB.cls(x.health)}">${C.mark(x.health, 10)}${esc(x.name)}<em>${esc(x.note)}</em></span>`).join('') +
      `<span class="chip chip-calm">${C.mark('up', 9)}${sc.seen.length - bad.length} others ok</span>`;
    return `<h4>${C.I.scope}Seen from</h4><div class="nv-chips">${chips}</div>`;
  }
  function nServerMini(s) {
    const m = (label, r) => `<div class="w-res"><span>${label}</span>${C.nvMeter(r.v, r.limit, s.withheld)}<b>${s.withheld ? '—' : Math.round(r.v) + '%'}</b></div>`;
    const pill = s.withheld ? '<span class="pill p-unk">CACHED</span>' : `<span class="pill p-${TB.cls(s.health)}">${s.pill || { up: 'UP', degraded: 'WARN', down: 'DOWN' }[s.health] || 'UNKNOWN'}</span>`;
    return { pill, meters: m('CPU', s.cpu) + m('Mem', s.mem) + m('Disk', s.disk) };
  }

  function native(kind, size, sc, o) {
    let body = '';
    const right = sc.attention.length ? nAttention(sc, size === 'm' ? 3 : 3) : nApps(sc, 6);
    if (kind === 'status') {
      if (size === 's') body = `<div class="w-col">${nStatusBlock(sc, false, 's')}${foot(sc)}</div>`;
      if (size === 'm') body = `<div class="w-split"><div class="w-col w-left">${nStatusBlock(sc, false, 'm')}${foot(sc)}</div><div class="w-col w-right">${right}</div></div>`;
      if (size === 'l') body = `<div class="w-col">${nStatusBlock(sc, true, 'l')}<div class="w-sec">${nSeen(sc)}</div><div class="w-sec">${right}</div>${foot(sc, true)}</div>`;
      if (size === 'xl') {
        const F = TB.fleet(sc);
        const G = TB._fleet.fleetGrid;
        const fleet = `<h4 class="${sc.attention.length ? 'w-gap' : ''}">${C.I.fleet}Fleet<em>${F.nodes} servers · ${F.providers} providers</em></h4>` +
          `${G(F, F.edges, 5)}${F.edges.length && F.servers.length ? '<div class="nv-sep fl-sep"></div>' : ''}${G(F, F.servers, 5)}`;
        body = `<div class="w-split xl"><div class="w-col">${nStatusBlock(sc, true, 'xl')}<div class="w-sec">${nSeen(sc)}</div><div class="w-sec">${sc.attention.length ? nAttention(sc, 3) : nApps(sc, 6)}</div>${foot(sc, true)}</div>
          <div class="w-col w-right">${sc.attention.length ? nApps(sc, 6) : ''}${fleet}</div></div>`;
      }
    }
    if (kind === 'server') {
      const s = o.node === 'mac' ? sc.mac : sc.servers[0];
      const x = nServerMini(s);
      const head = `<div class="w-srv-top">${TB.avatar(s, o.node === 'mac' ? C.I.laptop : null)}<div class="nv-server-name"><b>${esc(s.name)}</b><span>${esc(s.place)} · ${esc(TB.providerName(s.provider))}</span></div></div>`;
      const left = `<div class="w-col">${head}<div class="w-res-col">${x.meters}</div><div class="w-foot">${x.pill}<span>${s.withheld ? 'last ' : ''}${esc(s.updated)}</span></div></div>`;
      if (size === 's') body = left;
      else {
        const svc = (s.svc || []).map((v) => `<div class="w-app">${C.mark(s.withheld ? 'cached' : v.health, 9)}<span>${esc(v.name)}</span>${v.note ? `<em>${esc(v.note)}</em>` : ''}</div>`).join('');
        const ob = s.observes ? `<div class="w-obs">${C.I.scope}<span>From here</span><b>${C.mark(s.withheld ? 'cached' : s.observes.health, 9)}${esc(s.withheld ? 'not known' : s.observes.text)}</b></div>` : '';
        body = `<div class="w-split"><div class="w-col w-left">${left}</div><div class="w-col w-right"><h4>Services<em>${(s.svc || []).length}</em></h4>${svc}${ob}</div></div>`;
      }
    }
    const vars = TB.tokenCSS(o);
    return `<div class="wdg nv ${o.appearance} wd-${size} ${o.mode || ''}" style="${vars}width:${SIZE[size][0]}px;height:${SIZE[size][1]}px">${body}</div>`;
  }

  // ------------------------------------------------------------ terminal
  function terminal(kind, size, sc, o) {
    const p = T.pal(o);
    const S = T.S;
    const cols = COLS[size];
    const box = (title, right, body, opt) => T.box(title, right, body, opt);
    const statusBox = (w, short) => box(T.title(short ? 'STATUS' : 'STATUS'), [S(' ' + sc.age.replace(' ago', '') + ' ', 'muted')], T.tStatusBody(sc, p, w, { short }), { tint: T.statusTint(sc, p), cls: 'status' });
    const right = (w) => (sc.attention.length
      ? box(T.title('NEEDS ATTENTION', String(sc.attention.length + sc.more)), null, T.tAttentionBody(sc, w, 3, { compact: true }))
      : box(T.title('SERVICES', String(sc.apps.length) + ' apps'), null, T.tAppsBody(sc, w, { name: w > 30 ? 15 : 13, tight: w < 30, noNote: w < 30 })));
    let body = '';
    const head = (w) => T.tl([S('◉', 'acc'), S(' homelab', 'b')], [sc.live ? S('● LIVE', 'h-up b') : S('◌', 'h-unk b')], 'whead', w);
    if (kind === 'status') {
      if (size === 's') body = head(cols) + statusBox(cols - 2, true);
      if (size === 'm') body = head(cols) + `<div class="tcols"><div style="width:22ch">${statusBox(20, true)}</div><div style="width:28ch">${right(26)}</div></div>`;
      if (size === 'l') body = head(cols) + statusBox(cols - 2) + box(T.title('SEEN FROM', String(sc.seen.length)), null, T.tSeenBody(sc, cols - 2, 2)) + right(cols - 2);
      if (size === 'xl') {
        const lw = 54, rw = cols - lw - 1;
        const services = box(T.title('SERVICES', String(sc.apps.length) + ' apps'), null, T.tAppsBody(sc, rw - 2));
        // Fleet takes the lines left: each box costs 25 pt besides its
        // 16 pt lines, under the 16 pt head, inside 8 pt margins.
        const used = 16 + (sc.attention.length ? 25 + 16 * (Math.min(3, sc.attention.length) + 1) : 0) + 25 + 16 * sc.apps.length;
        const f = T.tFleetBody(sc, p, rw - 2, 4, Math.floor((SIZE.xl[1] - 16 - used - 25) / 16));
        const fleet = box(T.title('FLEET', String(f.nodes)), [S(' ' + f.providers + ' providers ', 'muted')], f.body);
        body = head(cols) + `<div class="tcols"><div style="width:${lw}ch">${statusBox(lw - 2)}${box(T.title('SEEN FROM', String(sc.seen.length)), null, T.tSeenBody(sc, lw - 2, 2))}${sc.servers.slice(0, 1).map((s) => box(T.serverTitle(s, p), T.serverPill(s), T.tServerBody(s, p, lw - 2))).join('')}</div>
          <div style="width:${rw}ch">${right(rw - 2)}${sc.attention.length ? services : ''}${fleet}</div></div>`;
      }
    }
    if (kind === 'server') {
      const s = o.node === 'mac' ? sc.mac : sc.servers[0];
      if (size === 's') {
        const w = cols - 2;
        const row = (label, r) => T.tl([S(label, 'muted'), S(s.withheld ? '   —' : (Math.round(r.v) + '%').padStart(4), s.withheld ? 'faint' : 'b'), S(' '), T.tBar(r.v, r.limit, w - 9, p, { withheld: s.withheld })], [], '', w);
        const bodyLines = row('CPU ', s.cpu) + row('MEM ', s.mem) + row('DSK ', s.disk) +
          T.tl([S(T.trunc(s.place, w - 8), 'muted')], [S(s.withheld ? 'last' : s.updated.replace(' ago', ''), 'faint')], '', w);
        const name = T.tl([S(TB.glyph(s.withheld ? 'cached' : s.health), 'h-' + (s.withheld ? 'unk' : TB.cls(s.health))), S(' ' + T.trunc(s.name, cols - 2), 'b')], [], 'whead', cols);
        body = name + box(T.title(s.kind.toUpperCase()), T.serverPill(s), bodyLines);
      } else {
        body = head(cols) + box(T.serverTitle(s, p), T.serverPill(s), T.tServerBody(s, p, cols - 2, { observes: true, bar: 22 }));
      }
    }
    return `<div class="wdg tv wd-${size} ${o.mode || ''}" style="${T.paletteVars(p)};width:${SIZE[size][0]}px;height:${SIZE[size][1]}px">${body}</div>`;
  }
  const len = (s) => [...s].length;

  TB.widget = function (kind, size, sc, o) {
    return (o.theme === 'tui' ? terminal : native)(kind, size, sc, o);
  };
  TB.widgetSize = SIZE;
})();
