/* ════════════════════════════════════════════════════════════════════
   实时路由舞台：magpie 路由页 .rt-stage 的壁纸版移植
   （internal/gui/assets/plugins/routing/client.js 的舞台部分）。

   为什么不再内嵌 magpie 原页：原页要靠 `magpie web` 当后端，那是又一个
   magpie 进程——它和 magpie 主程序各自轮换同一份 Claude Code / Codex 的
   OAuth 令牌，两边一抢，Claude Code 的登录就断断续续。这里只读主程序网关
   已经在给的 `/v1/magpie/trace`（只读、增量 after=seq），不再多起任何进程。

   移植的是舞台本身：左侧 agent、中间 magpie、右侧账号行；线是 magpie 的
   curve()，喜鹊叼着请求点沿线飞（fly / via / pose / play），账号作答时点
   停在线头闪烁，回信由另一只喜鹊带回；失败的点回到 magpie 再转给下一个。
   座次（seated / seat / tryseat）、行上的话、点亮规则（render / lightRow）
   与原页一致。没搬的：路由组折叠、请求账本、回放、字幕——壁纸上用不到。
   ═══════════════════════════════════════════════════════════════════ */
(function () {
  'use strict';

  const NS = 'http://www.w3.org/2000/svg';
  const LINGER = 12e3;   // 一个 agent 最后一次请求在舞台上停留多久
  const LIVE = 4;        // 回到画面时最多续飞几个在途请求
  const KEEP = 60;       // 与网关一致：只留最近 60 条

  // 与 magpie 的 hueOf 一致：有官方色用官方色，其余按 id 哈希取备用色，没有红色
  const HUES = {
    claude: '#d97757', codex: '#6366f1', gemini: '#0ea5e9', copilot: '#a855f7', cursor: '#14b8a6', opencode: '#eab308',
    crush: '#ec4899', goose: '#84cc16', pi: '#10b981', omp: '#d946ef', omo: '#7c3aed', dsh: '#06b6d4', commandcode: '#f97316',
    mimocode: '#3b82f6', deveco: '#3c99cc',
  };
  const SPARE = ['#8b5cf6', '#22c55e', '#0d9488', '#0891b2', '#ca8a04', '#db2777', '#2563eb', '#65a30d'];
  function hueOf(id) {
    if (HUES[id]) return HUES[id];
    let h = 0;
    for (const c of String(id || '')) h = (h * 31 + c.charCodeAt(0)) >>> 0;
    return SPARE[h % SPARE.length];
  }

  // magpie 自己的中文（i18n.js / plugins/routing/i18n.js 的 zh）
  const MODES = {
    '': '智能', order: '按顺序', rotate: '轮流', usage: '最少使用', pace: '重置前用完', manual: '手动',
    weight: '按权重', free: '免费优先', cheap: '最便宜优先', fast: '速度优先',
  };
  const FAIL = {
    rate: '限流', credit: '余额不足', quota: '额度用尽', other: '失败', auth: '需要重新登录', canceled: '已取消',
    foreign: '另一账号的推理', floor: '回复过短', verify: '需要验证', refused: '被安全过滤拒绝', shape: '请求无法理解',
    sight: '不收图片', proxy: '代理不可达', effort: '套餐不含此推理强度', overflow: '超出模型长度', room: '回复超出剩余窗口',
    slow: '首字太慢', prompt: 'Agent 提示词被拒', restricted: '账号被厂商限制',
  };
  const failWord = (why) => FAIL[why] || '失败';
  const AGENT_NAMES = {
    claude: 'Claude Code', 'claude-desktop': 'Claude Desktop', codex: 'Codex', gemini: 'Gemini CLI', copilot: 'Copilot',
    cursor: 'Cursor', opencode: 'OpenCode', crush: 'Crush', goose: 'Goose', pi: 'Pi', dsh: 'dsh',
  };
  const agentName = (id) => AGENT_NAMES[id] || String(id || 'agent').split(/[-_]/).map((w) => w ? w[0].toUpperCase() + w.slice(1) : w).join(' ');

  // 与原页同一只喜鹊（FLIER）：面朝右，点在喙尖，翅膀从肩部拍动
  const FLIER = '<g class="rt-lift"><g transform="scale(1.2) translate(-6.5 3.2)">'
    + '<path class="wing far" d="M-14.5 -3.4C-16.5 -9.5 -14.2 -15 -8.6 -18.6C-9.4 -12.6 -9.6 -7.4 -9.2 -3.2Z"/>'
    + '<path class="tail" d="M-31.5 3.1L-18.6 -1.8L-17.4 1.2L-30.8 4.6Z"/>'
    + '<ellipse class="body" cx="-12.2" cy="-1.4" rx="7.6" ry="3.9"/>'
    + '<ellipse class="belly" cx="-12.8" cy="0.4" rx="4.3" ry="1.6"/>'
    + '<circle class="body" cx="-4.9" cy="-3.7" r="3.1"/>'
    + '<path class="body" d="M-2.3 -4.8L1.4 -3.3L-2.3 -2.2Z"/>'
    + '<g class="wing near"><path d="M-15.6 -3.2C-17.8 -10.2 -15.2 -16.4 -8.4 -20.4C-9.3 -13.6 -9.4 -7.8 -8.8 -2.8Z"/>'
    + '<path class="bar" d="M-14.6 -5.6C-15.4 -10.4 -13.8 -14.4 -10.4 -17.2"/></g>'
    + '</g></g>';

  const el = (tag, cls, text) => {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  };
  const setText = (e, s) => { if (e.textContent !== s) e.textContent = s; };
  const setAttr = (e, k, v) => { if (e.getAttribute(k) !== v) e.setAttribute(k, v); };
  const rerun = (e, cls) => { e.classList.remove(cls); void e.offsetWidth; e.classList.add(cls); };
  const at = (s) => s ? Date.parse(s) : 0;
  const pct = (n) => Math.round(n) + '%';
  const tokens = (n) => n >= 1e6 ? (n / 1e6).toFixed(1) + 'M' : n >= 1e3 ? (n / 1e3).toFixed(1) + 'k' : String(Math.round(n));
  const num = new Intl.NumberFormat('zh-CN', { maximumFractionDigits: 2 });
  function dur(ms) {
    const m = Math.max(1, Math.round(ms / 60e3));
    if (m < 60) return m + ' 分钟';
    const h = Math.round(m / 60);
    return h < 48 ? h + ' 小时' : Math.round(h / 24) + ' 天';
  }
  const clock = (s) => new Date(at(s)).toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' });
  const tryOk = (tr) => tr.status < 400 && !tr.fail;
  const whole = (r) => { r.order ||= []; r.tries ||= []; r.left ||= []; return r; };

  // 座次：同一账号同一模型是一个座（seat），见原页 seat / tried / tryseat
  const seat = (x) => x.id + '\u0000' + (x.model || '') + (x.fixed ? ':' + x.fixed : '');
  const tried = (r, tr) => r.order.find((x) => seat(x) === seat(tr))
    || r.order.find((x) => x.id === tr.id && (x.model || '') === (tr.model || ''))
    || r.order.find((x) => x.id === tr.id);
  const tryseat = (r, tr) => seat(tried(r, tr) || tr);
  const heldOut = (w) => !w.held && !!(w.capped || w.noCredits || w.window);
  // seated：账号各坐各的位置，不随本次权衡的先后挪动——组员按组里的顺序，
  // 备用在后，同一服务商按自己的顺序；被抢先的那个亮起来，列表本身不动
  function seated(r) {
    const members = r.group?.members || [];
    const key = (w) => {
      let m = members.indexOf(w.provider + '/' + w.model + (w.fixed ? ':' + w.fixed : ''));
      if (m < 0) m = members.findIndex((x) => x.startsWith(w.provider + '/'));
      return [w.fallback ? 1 : 0, m < 0 ? members.length : m, w.name || w.provider, w.aside ? 1 : 0, w.rank || 0, w.who || '', w.id];
    };
    const cmp = (x, y) => {
      for (let i = 0; i < x.length; i++) if (x[i] !== y[i]) return typeof x[i] === 'number' ? x[i] - y[i] : String(x[i]).localeCompare(String(y[i]));
      return 0;
    };
    const on = new Set(r.order.map(seat));
    return [...r.order, ...(r.left || []).filter((w) => heldOut(w) && !on.has(seat(w)))]
      .map((w) => [key(w), w]).sort((a, b) => cmp(a[0], b[0])).map(([, w]) => w);
  }
  const setOf = (r) => r.order.map(seat).sort().join('\n');

  // 线：原页 curve()——S 形三次曲线，拐点在 mx
  const curve = (x0, y0, mx, x3, y3) => `M${x0} ${y0} C${mx} ${y0} ${mx} ${y3} ${x3} ${y3}`;

  // flat：把一条只含 M/L/Q/C 的 d 拆成密集折线，供 pointAt 取点（原页 flat / pointAt）
  function flat(d) {
    const n = d.match(/[A-Za-z]|-?(?:\d+\.?\d*|\.\d+)(?:e[-+]?\d+)?/gi) || [], k = { M: 2, L: 2, Q: 4, C: 6 };
    const xs = [], ys = [], len = [];
    const to = (x, y) => {
      const j = xs.length - 1;
      len.push(j < 0 ? 0 : len[j] + Math.hypot(x - xs[j], y - ys[j]));
      xs.push(x); ys.push(y);
    };
    let c = '';
    for (let i = 0; i < n.length;) {
      if (/[A-Za-z]/.test(n[i])) { c = n[i++]; continue; }
      if (!k[c] || (c === 'M' && xs.length)) return null;
      const a = n.slice(i, i += k[c]).map(Number);
      if (a.length < k[c] || a.some(isNaN)) return null;
      if (c === 'M') { to(a[0], a[1]); c = 'L'; continue; }
      const P = [xs[xs.length - 1], ys[ys.length - 1], ...a];
      if (c === 'L') { to(a[0], a[1]); continue; }
      let hull = 0;
      for (let j = 2; j < P.length; j += 2) hull += Math.hypot(P[j] - P[j - 2], P[j + 1] - P[j - 1]);
      const steps = Math.max(1, Math.ceil(hull / 2));
      for (let j = 1; j <= steps; j++) {
        const t = j / steps, u = 1 - t;
        const w = c === 'Q' ? [u * u, 2 * u * t, t * t] : [u * u * u, 3 * u * u * t, 3 * u * t * t, t * t * t];
        let x = 0, y = 0;
        w.forEach((wi, q) => { x += wi * P[2 * q]; y += wi * P[2 * q + 1]; });
        to(x, y);
      }
    }
    return xs.length > 1 && len[len.length - 1] > 0 ? { xs, ys, len } : null;
  }
  const measured = new WeakMap();
  function measure(p) {
    const d = p.isConnected && p.getAttribute('d');
    if (!d) return null;
    let m = measured.get(p);
    if (!m || m.d !== d) measured.set(p, m = { d, f: flat(d) });
    return m.f ? m : null;
  }
  const pathLength = (p) => { const m = measure(p); return m ? m.f.len[m.f.len.length - 1] : 0; };
  function pointAt(p, s) {
    const { xs, ys, len } = measure(p).f;
    s = Math.max(0, Math.min(len[len.length - 1], s));
    let lo = 0, hi = len.length - 1;
    while (hi - lo > 1) { const mid = (lo + hi) >> 1; if (len[mid] <= s) lo = mid; else hi = mid; }
    const f = len[hi] > len[lo] ? (s - len[lo]) / (len[hi] - len[lo]) : 0;
    return { x: xs[lo] + (xs[hi] - xs[lo]) * f, y: ys[lo] + (ys[hi] - ys[lo]) * f };
  }
  // tip：一条线的头或尾，以及在那里的走向（原页 tip / wireEnds）
  const tip = (p, atEnd, back) => () => {
    const m = measure(p);
    if (!m) return null;
    const { xs, ys } = m.f, i = atEnd ? xs.length - 1 : 0, j = atEnd ? Math.max(0, i - 3) : Math.min(xs.length - 1, 3);
    let tx = atEnd ? xs[i] - xs[j] : xs[j] - xs[i], ty = atEnd ? ys[i] - ys[j] : ys[j] - ys[i];
    if (back) { tx = -tx; ty = -ty; }
    const h = Math.hypot(tx, ty) || 1;
    return { x: xs[i], y: ys[i], tx: tx / h, ty: ty / h };
  };

  function MagpieStage(box, opts = {}) {
    const mask = opts.mask || ((s) => s);
    const shown = () => !document.hidden && box.isConnected && box.offsetWidth > 0;
    const still = () => matchMedia('(prefers-reduced-motion: reduce)').matches;

    // ---------- 舞台的骨架（与原页 #rt 内 .rt-stage 同构） ----------
    const rt = el('section', 'rt');
    const stage = el('div', 'rt-stage');
    const wires = document.createElementNS(NS, 'svg');
    wires.setAttribute('class', 'rt-wires');
    const srcs = el('div', 'rt-srcs');
    const hub = el('div', 'rt-node rt-hub');
    const logo = el('img', 'rt-bird');
    logo.src = 'magpie-bird.svg';
    logo.alt = '';
    const hubSub = el('small'), chip = el('i');
    hub.append(logo, el('b', '', 'magpie'), hubSub, chip);
    const list = el('ol', 'rt-accts');
    const sky = document.createElementNS(NS, 'svg');
    sky.setAttribute('class', 'rt-sky');
    stage.append(wires, srcs, hub, list, sky);
    rt.append(stage);
    box.replaceChildren(rt);
    const path = () => { const p = document.createElementNS(NS, 'path'); wires.appendChild(p); return p; };

    // ---------- 状态 ----------
    const routes = new Map();
    let seq = 0, loaded = false, by = null, cur = null, gateway = '127.0.0.1:3425';
    const agents = new Map(); // agent → { node, ic, name, sub, wire }
    let rows = new Map();     // seat → { li, wire, st, bi, tg, w, rid }
    let sets = [];
    const playing = new Map();
    const flying = new Map(); // 点 → { id: 它所在的座, agent }
    const holds = new Map();  // 点 → 它停着等回答的那一行
    let gen = 0, trips = [], waiters = [], flipUntil = 0;
    let seen = false, lastFrame = 0, ticking = 0;
    const busy = () => trips.length > 0 || performance.now() < flipUntil;
    const now = () => Date.now();
    const src = () => routes;
    const newest = () => { let r = null; for (const x of routes.values()) if (!r || x.id > r.id) r = x; return r; };

    function kick() {
      if (ticking || !shown()) return;
      if (seen) lastFrame = performance.now();
      ticking = requestAnimationFrame(frame);
    }
    const fly = (dot, bird, legs, ms) => new Promise((res) => {
      if (!shown()) { res(); return; }
      const tr = { dot, bird, legs, t0: performance.now(), ms: still() ? 0 : ms, res, g: gen };
      pose(tr, 0);
      trips.push(tr);
      kick();
    }).finally(() => { for (const l of legs) if (l.j) l.p.remove(); });
    const until = (f) => f() ? Promise.resolve() : new Promise((res) => waiters.push({ f, res }));
    const wake = () => { const w = waiters; waiters = []; for (const x of w) if (x.f()) x.res(); else waiters.push(x); };

    // via：穿过 magpie 从一条线到下一条的弧（原页 via）
    function via(from, to) {
      const p = document.createElementNS(NS, 'path');
      p.setAttribute('class', 'via');
      sky.appendChild(p);
      const j = () => {
        const a = from(), b = to();
        if (!a || !b) { p.removeAttribute('d'); return; }
        const dx = b.x - a.x, dy = b.y - a.y, dist = Math.hypot(dx, dy);
        let c1, c2;
        if (dist < 4) {
          const k = Math.min(hub.offsetWidth, hub.offsetHeight) * .42, m = k * .6, nx = a.ty, ny = -a.tx;
          c1 = [a.x + a.tx * k - nx * m, a.y + a.ty * k - ny * m];
          c2 = [b.x - b.tx * k + nx * m, b.y - b.ty * k + ny * m];
        } else {
          const k = dist * .38, l = Math.min(16, dist * .12), nx = dy / dist, ny = -dx / dist;
          c1 = [a.x + a.tx * k + nx * l, a.y + a.ty * k + ny * l];
          c2 = [b.x - b.tx * k + nx * l, b.y - b.ty * k + ny * l];
        }
        setAttr(p, 'd', `M${a.x} ${a.y} C${c1[0]} ${c1[1]} ${c2[0]} ${c2[1]} ${b.x} ${b.y}`);
      };
      j();
      return { p, j };
    }

    // ---------- 布局：读一遍每个盒子，再画线（原页 layout） ----------
    function layout() {
      const sw = stage.offsetWidth, sh = stage.offsetHeight;
      if (!sw) return;
      const r = stage.getBoundingClientRect(), z = r.width / sw || 1;
      const boxes = new Map();
      const b = (e) => {
        let v = boxes.get(e);
        if (v) return v;
        const x = e.getBoundingClientRect();
        v = { l: (x.left - r.left) / z, r: (x.right - r.left) / z, t: (x.top - r.top) / z, b: (x.bottom - r.top) / z };
        v.cx = (v.l + v.r) / 2; v.cy = (v.t + v.b) / 2;
        boxes.set(e, v);
        return v;
      };
      const h = b(hub), low = b(srcs).b, out = [];
      for (const a of agents.values()) {
        const s = b(a.node), mx = (s.r + h.l) / 2;
        out.push([a.wire, h.l > s.r ? curve(s.r, s.cy, mx, h.l, h.cy) : `M${s.cx} ${s.b} L${h.cx} ${h.t}`]);
      }
      const fromHub = (a) => {
        if (a.l > h.r) return curve(h.r, h.cy, (h.r + a.l) / 2, a.l, a.cy);
        // 窄时账号挂在 magpie 下面：沿它们左侧一条竖巷下去
        const x = a.l - 12, y = Math.max(h.b, low - 8);
        return `M${h.cx} ${h.b} L${h.cx} ${y} C${h.cx} ${y + 22} ${x} ${y + 2} ${x} ${y + 24} L${x} ${a.cy - 10} Q${x} ${a.cy} ${a.l} ${a.cy}`;
      };
      for (const row of rows.values()) out.push([row.wire, row.li.isConnected ? fromHub(b(row.li)) : null]);
      const vb = `0 0 ${sw} ${sh}`;
      for (const svg of [wires, sky]) setAttr(svg, 'viewBox', vb);
      for (const [p, d] of out) {
        if (d === null) p.removeAttribute('d');
        else setAttr(p, 'd', d);
      }
      for (const [dot, row] of holds) pose({ dot, legs: [{ p: row.wire }] }, 1);
    }

    // staged：舞台上演哪些请求——在飞的、每个 agent 停留中的最后一次，最多 4 个 agent
    function staged() {
      const n = now(), last = new Map();
      const rs = [...routes.values()].sort((a, b) => a.id - b.id);
      for (const r of rs) last.set(r.agent, r);
      const out = rs.filter((r) => playing.has(r.id) || (last.get(r.agent) === r && (!r.done || at(r.time) + (r.ms || 0) > n - LINGER)));
      if (cur && routes.has(cur.id) && !out.includes(routes.get(cur.id))) out.push(routes.get(cur.id));
      const ags = [...new Set(out.map((r) => r.agent))].slice(-4);
      return out.filter((r) => ags.includes(r.agent)).sort((a, b) => a.id - b.id);
    }

    function agentNode(id) {
      let a = agents.get(id);
      if (a) return a;
      const node = el('div', 'rt-node rt-src'), ic = el('span', 'rt-ic'), name = el('b'), sub = el('small');
      ic.textContent = agentName(id).slice(0, 1);
      node.append(ic, name, sub);
      a = { node, ic, name, sub, wire: path() };
      node.style.setProperty('--agent', hueOf(id));
      a.wire.style.setProperty('--agent', hueOf(id));
      agents.set(id, a);
      return a;
    }

    function makeRow(w) {
      const li = el('li'), b = el('b');
      b.append(el('span', 'who', mask(w.who || w.name || w.provider || w.id)), ' ',
        el('span', '', w.fallback ? w.name || '' : w.kind === 'provider' ? '' : w.plan || ''),
        el('code', 'mdl', w.fixed ? `${w.model}:${w.fixed}` : w.model || ''));
      if (w.fallback) b.append(el('small', 'fb', '备用'));
      const st = el('em'), bar = el('div', 'bar'), bi = el('i'), tg = el('span', 'tag');
      bar.append(bi);
      li.append(el('i', 'dot'), b, st, bar, tg);
      return { li, wire: path(), st, bi, tg, w };
    }

    function sync(force) {
      if (!shown()) return;
      const rs = staged();
      if (rs.length) rebuild(rs, force);
    }
    function rebuild(rs, force) {
      cur = routes.get(rs[rs.length - 1].id) || rs[rs.length - 1];
      if (force) {
        for (const row of rows.values()) row.wire.remove();
        rows = new Map();
        list.replaceChildren();
        for (const a of agents.values()) a.wire.remove();
        agents.clear();
        srcs.replaceChildren();
      }
      // agents
      const ags = [...new Set(rs.map((r) => r.agent))];
      for (const [id, a] of agents) if (!ags.includes(id)) { a.node.remove(); a.wire.remove(); agents.delete(id); }
      const keep = [...agents.keys()];
      const nodes = [...keep, ...ags.filter((a) => !keep.includes(a))].map((id) => agentNode(id).node);
      if (nodes.some((x, i) => srcs.children[i] !== x) || srcs.children.length !== nodes.length) srcs.replaceChildren(...nodes);
      srcs.classList.toggle('many', ags.length > 1);
      for (const id of ags) {
        const a = agents.get(id), r = rs.filter((x) => x.agent === id).pop();
        setText(a.name, agentName(id));
        setText(a.sub, (r.model || '').replace(/^[^/]+\//, ''));
      }
      // 各账号组取最新那次
      const latest = new Map();
      for (const r of rs) latest.set(setOf(r), r);
      sets = [...sets.filter((k) => latest.has(k)), ...[...latest.keys()].filter((k) => !sets.includes(k))];
      const ids = [], has = new Set(), wOf = new Map(), rOf = new Map();
      for (const k of sets) for (const x of seated(latest.get(k))) { const id = seat(x); if (!has.has(id)) { has.add(id); ids.push(id); } }
      for (const r of rs) for (const w of [...r.order, ...(r.left || [])]) { wOf.set(seat(w), w); rOf.set(seat(w), r.id); }
      const before = new Map([...rows].filter(([, row]) => row.li.isConnected).map(([id, row]) => [id, row.li.getBoundingClientRect().top]));
      for (const [id, row] of rows) if (!has.has(id)) { row.li.remove(); row.wire.remove(); rows.delete(id); }
      if (list.querySelector('.idle')) list.replaceChildren();
      for (const id of ids) {
        let row = rows.get(id);
        if (!row) {
          row = makeRow(wOf.get(id));
          rows.set(id, row);
          if (before.size && !still()) row.li.classList.add('new');
        }
        row.w = wOf.get(id);
        row.rid = rOf.get(id);
      }
      const els = ids.map((id) => rows.get(id).li);
      if (els.some((x, i) => list.children[i] !== x) || list.children.length !== els.length) list.replaceChildren(...els);
      // FLIP：从原来的位置滑到新位置
      const z = (stage.getBoundingClientRect().width / stage.offsetWidth) || 1;
      let moved = false;
      const placed = [...rows].filter(([, row]) => row.li.isConnected);
      const dys = still() ? [] : placed.map(([id, row]) => before.has(id) ? (before.get(id) - row.li.getBoundingClientRect().top) / z : 0);
      placed.forEach(([, row], i) => {
        if (!dys[i]) return;
        moved = true;
        row.li.style.transition = 'none';
        row.li.style.transform = `translateY(${dys[i]}px)`;
      });
      if (moved) {
        void list.offsetWidth;
        for (const [, row] of placed) { row.li.style.transition = ''; row.li.style.transform = ''; }
        flipUntil = performance.now() + 520;
        kick();
      }
      header(cur);
      layout();
      opts.onResize?.();
    }

    // 中间的 magpie：谁在路由、按什么方式
    function header(r) {
      const f = r.order.find((x) => !x.fallback) || r.order[0];
      const g = r.group;
      const routing = g ? g.routing || '' : f?.routing || '';
      const on = r.order.filter((x) => !x.fallback).length;
      setText(chip, MODES[routing] || routing || MODES['']);
      chip.hidden = (!g && on === 1) || (!r.order.length && !g);
      hubText();
    }
    function hubText() {
      const who = by?.serves ? `${by.serves} (pid ${by.pid}) · ` : '';
      setText(hubSub, who + gateway);
    }

    function lightRow(li, wire, on, live) {
      li.classList.toggle('on', on);
      li.classList.toggle('now', on && live);
      wire.classList.toggle('live', on && live);
      wire.classList.toggle('lit', on && !live);
    }

    // 一行说的话：休息、作答中、或路由按什么权衡了它（原页 render）
    function quota(w, used, vars = '') {
      if (w.balance != null) return `剩余 ${num.format(w.balance)} ${w.unit || ''}`.trim() + vars;
      return (w.limit > 0 ? `${num.format(w.amount || 0)} / ${num.format(w.limit)} ${w.unit || ''}`.trim() + ' · ' : '')
        + `已用 ${pct(w.used || 0)}` + used + vars;
    }
    function render() {
      if (!cur) return;
      hubText();
      const n = now(), rs = staged();
      const trying = new Set(), busyAgents = new Set();
      for (const r of rs) for (const tr of r.tries) if (!tr.done) { trying.add(tryseat(r, tr)); busyAgents.add(r.agent); }
      const onWire = new Set();
      for (const f of flying.values()) { onWire.add(f.id); busyAgents.add(f.agent); }
      const found = new Map();
      const findings = (r) => {
        let f = found.get(r);
        if (f) return f;
        const answered = new Set(), rests = new Map(), gave = new Map(), went = new Map();
        for (const w of r.order) if (w.rest) rests.set(w.id, w.rest);
        r.tries.forEach((tr, i) => {
          const last = i === r.tries.length - 1;
          if (tr.done && tryOk(tr)) answered.add(tryseat(r, tr));
          else if (tr.done && !tr.rest && !tr.again && !tr.earlier && r.done && last) gave.set(tryseat(r, tr), tr);
          else if (tr.done && !tr.rest && !tr.again && !tr.credits && !last) went.set(tryseat(r, tr), tr);
          if (tr.rest) rests.set(tr.id, tr.rest);
        });
        for (const tr of r.tries) if (tr.done && tryOk(tr)) rests.delete(tr.id);
        found.set(r, f = { answered, rests, gave, went });
        return f;
      };
      for (const [id, row] of rows) {
        const r = routes.get(row.rid) || cur, { answered, rests, gave, went } = findings(r);
        const w = row.w, rest = rests.get(w.id), resting = rest && at(rest.until) > n;
        let s;
        if (w.unlisted) s = '厂商未列出此模型';
        else if (resting) s = `${failWord(rest.why)} · ${dur(at(rest.until) - n)}后恢复`;
        else if (w.window) s = '请求超出它的上下文窗口 · 跳过';
        else if (trying.has(id)) s = r.id !== cur.id && agents.size <= 1 ? '在回答另一个请求…' : '回答中…';
        else if (answered.has(id)) s = agents.size > 1 ? `回答了 ${agentName(r.agent)}` : '回答了这个请求';
        else if (gave.has(id)) s = `${gave.get(id).status} · ${failWord(gave.get(id).fail)} · 已交给 ${agentName(r.agent)}`;
        else if (went.has(id)) s = `${went.get(id).status} · ${failWord(went.get(id).fail)} · 已转给下一个`;
        else if (w.sunk) s = `${clock(w.sunk)} 被限流 · 排在最后`;
        else if (w.free) s = '免费 · 不花额度';
        else if (w.known) {
          const soon = at(w.usedRenews) || 0;
          s = !w.routing && w.used >= 98 && w.credits ? quota(w, ' · 使用 Credits')
            : !w.routing && w.used >= 98 ? quota(w, ' · 几乎用尽')
            : !w.routing && w.used >= 90 ? quota(w, ' · 留到最后')
            : soon > n ? quota(w, '', ` · ${dur(soon - n)}后重置`) : quota(w, '');
        } else if (w.kind === 'account') s = '剩余额度未知';
        else if (w.routing === 'usage') s = `最近 ${tokens(w.tokens || 0)} token`;
        else s = w.kind === 'key' ? 'API 密钥' : '一个 Key';
        setText(row.st, s);
        const bar = w.known && !w.free && w.balance == null;
        row.li.classList.toggle('nobar', !bar);
        row.bi.style.width = bar ? Math.max(0, Math.min(100, w.used || 0)) + '%' : '0';
        const live = !resting && (trying.has(id) || onWire.has(id));
        const on = live || (!resting && answered.has(id));
        lightRow(row.li, row.wire, on, live);
        row.li.classList.toggle('low', !!(!w.routing && w.known && w.used >= 90));
        row.li.classList.toggle('rest', !!resting || gave.has(id));
        row.li.classList.toggle('left', !!w.unlisted || !!w.window);
        if (on) row.wire.style.setProperty('--agent', hueOf(r.agent));
        row.wire.classList.toggle('rest', !!resting || !!w.unlisted || !!w.window);
      }
      for (const [id, a] of agents) a.wire.classList.toggle('live', busyAgents.has(id));
    }

    // ---------- 飞：一只喜鹊叼着请求去，另一只带着回信回来（原页 play） ----------
    function bird(kind) {
      if (still() || !shown()) return null;
      const g = document.createElementNS(NS, 'g');
      g.setAttribute('class', 'rt-flier ' + kind);
      g.innerHTML = FLIER;
      sky.appendChild(g);
      return g;
    }
    function away(b) {
      if (!b) return;
      b.classList.add('away');
      setTimeout(() => b.remove(), 450);
    }
    function packet() {
      const dot = document.createElementNS(NS, 'circle');
      dot.setAttribute('r', 4.5);
      dot.setAttribute('class', 'pkt');
      dot.setAttribute('visibility', 'hidden');
      sky.appendChild(dot);
      return dot;
    }
    const tick = (node) => { if (!still()) rerun(node, 'tick'); };
    const home = (row, A) => [{ p: row.wire, rev: true }, via(tip(row.wire, false, true), tip(A.wire, true, true)), { p: A.wire, rev: true }];

    async function play(id, synced) {
      let r = routes.get(id);
      if (!r) return;
      const g = gen;
      playing.set(id, g);
      cur = r;
      if (!synced) sync();
      render();
      const A = agents.get(r.agent);
      if (!A) { if (playing.get(id) === g) playing.delete(id); return; }
      const dot = packet();
      dot.style.setProperty('--agent', hueOf(r.agent));
      let carrier = bird('req'), from = null, back = null;
      const rt = () => routes.get(id) || { ...r, done: true, tries: r.tries.map((x) => ({ ...x, done: true })) };
      try {
        tick(A.node);
        if (!r.tries.length) { // 还没选出账号：先飞到 magpie 等着
          await fly(dot, carrier, [{ p: A.wire }], 620);
          from = tip(A.wire, true);
          tick(hub);
        }
        for (let i = 0; g === gen;) {
          r = rt();
          if (!routes.has(id)) break;
          if (i >= r.tries.length) {
            if (r.done) break;
            await until(() => g !== gen || rt().tries.length > i || rt().done);
            continue;
          }
          const row = rows.get(tryseat(r, r.tries[i]));
          if (!row) { i++; continue; }
          flying.set(dot, { id: tryseat(r, r.tries[i]), agent: r.agent });
          if (!carrier) carrier = bird('req');
          if (from) tick(hub);
          const out = [via(from || tip(A.wire, true), tip(row.wire, false)), { p: row.wire }];
          await fly(dot, carrier, from ? out : [{ p: A.wire }, ...out], from ? 900 : 1400);
          if (g !== gen) break;
          // 在账号那里放下：它作答时点停在线头
          away(carrier);
          carrier = null;
          dot.classList.add('held');
          holds.set(dot, row);
          layout();
          await until(() => g !== gen || !rt().tries[i] || rt().tries[i].done);
          holds.delete(dot);
          if (g !== gen) break;
          r = rt();
          if (!routes.has(id)) break;
          const tr = r.tries[i];
          dot.classList.remove('held');
          if (tryOk(tr)) {
            await until(() => g !== gen || rt().done);
            if (g !== gen) break;
            render();
            dot.classList.add('back');
            dot.setAttribute('r', 4);
            back = bird('res');
            await fly(dot, back, home(row, A), 1400);
            flying.delete(dot);
            away(back);
            tick(A.node);
            break;
          }
          rerun(row.li, 'hit');
          row.li.classList.add('tagged');
          row.tg.textContent = `${tr.status} · ${failWord(tr.fail)}`;
          setTimeout(() => row.li.classList.remove('tagged'), 1800);
          render();
          dot.classList.add('back', 'err');
          back = bird('res');
          if (!tr.rest && !tr.credits && (!tr.again || tr.gone)) { // 这就是答复：错误交回 agent
            await fly(dot, back, home(row, A), 1350);
            flying.delete(dot);
            away(back);
            tick(A.node);
            break;
          }
          // 回到 magpie，由它转给下一个
          await fly(dot, back, [{ p: row.wire, rev: true }], 620);
          flying.delete(dot);
          away(back);
          dot.classList.remove('back', 'err');
          from = tip(row.wire, false, true);
          i++;
        }
      } finally {
        away(carrier);
        away(back);
        flying.delete(dot);
        holds.delete(dot);
        dot.remove();
        if (playing.get(id) === g) playing.delete(id);
        render();
      }
    }

    function stopPlays() {
      gen++; flying.clear(); holds.clear(); playing.clear();
      for (const p of sky.querySelectorAll('.pkt, .rt-flier, .via')) p.remove();
      wake();
    }

    function pose(tr, e) {
      for (const l of tr.legs) if (l.j) l.j();
      const lens = tr.legs.map((l) => pathLength(l.p));
      const total = lens.reduce((a, b) => a + b, 0);
      if (!total) return;
      const point = (d) => {
        d = Math.max(0, Math.min(total, d));
        let i = 0;
        while (i < lens.length - 1 && (d > lens[i] || !lens[i])) { d -= lens[i]; i++; }
        const l = tr.legs[i];
        return pointAt(l.p, l.rev ? lens[i] - d : d);
      };
      // 线都止于卡片，天空在卡片下：起落各让开一点，停着的点才看得全
      const edge = Math.min(6, total / 4), d = edge + e * (total - 2 * edge), pt = point(d);
      setAttr(tr.dot, 'cx', String(pt.x));
      setAttr(tr.dot, 'cy', String(pt.y));
      tr.dot.removeAttribute('visibility');
      const b = tr.bird;
      if (!b) return;
      const p0 = point(d - 3), p1 = point(d + 3);
      let vx = p1.x - p0.x, vy = p1.y - p0.y;
      if (Math.abs(vx) + Math.abs(vy) < .01) { vx = b._vx ?? (tr.legs[0].rev ? -1 : 1); vy = 0; }
      b._vx = vx;
      const aim = Math.max(-24, Math.min(24, Math.atan2(vy, Math.abs(vx)) * 180 / Math.PI));
      b._a = b._a === undefined || b._flip !== (vx < 0) ? aim : b._a + (aim - b._a) * .12;
      b._flip = vx < 0;
      b.setAttribute('transform', `translate(${pt.x.toFixed(1)} ${pt.y.toFixed(1)}) scale(${b._flip ? -1 : 1} 1) rotate(${b._a.toFixed(1)})`);
    }

    const underWay = () => [...routes.values()].filter((r) => !r.done).sort((a, b) => a.id - b.id).slice(-LIVE);
    function resume() {
      stopPlays();
      if (!loaded) return;
      cur = newest();
      if (cur) sync(true); else empty();
      for (const r of underWay()) play(r.id);
      render();
    }
    // 只在画面可见且有东西在动时要帧；空闲的舞台一帧也不要（原页 #2827）
    function frame(ts) {
      ticking = 0;
      const vis = shown();
      if (vis && (!seen || ts - lastFrame > 1000)) resume();
      seen = vis;
      lastFrame = ts;
      if (vis) {
        const live = trips; trips = [];
        for (const tr of live) {
          if (tr.g !== gen) { tr.res(); continue; }
          const k = tr.ms ? Math.min(1, Math.max(0, (ts - tr.t0) / tr.ms)) : 1;
          try { pose(tr, (1 - Math.cos(Math.PI * k)) / 2); } catch { tr.res(); continue; }
          if (k >= 1) tr.res(); else trips.push(tr);
        }
        if (ts < flipUntil) layout();
      } else {
        for (const tr of trips) tr.res();
        trips = [];
        seen = false;
        wake();
      }
      if (vis && busy() && !ticking) ticking = requestAnimationFrame(frame);
    }
    document.addEventListener('visibilitychange', () => { if (shown()) kick(); });

    function empty() {
      for (const row of rows.values()) row.wire.remove();
      rows = new Map();
      for (const a of agents.values()) a.wire.remove();
      agents.clear();
      srcs.replaceChildren();
      const li = el('li', 'idle', loaded ? '还没有请求经过 magpie' : '正在读取网关路由…');
      list.replaceChildren(li);
      layout();
    }
    empty();
    new ResizeObserver(() => layout()).observe(stage);

    // ---------- 网关 trace：增量合并（原页 poll 的同一套合并规则） ----------
    function update(d) {
      if (!d || !Array.isArray(d.routes)) return;
      const pid = d.pid ?? d.by?.pid;
      const fromOther = loaded && pid != null && by && pid !== by.pid;
      by = pid != null ? { pid, serves: d.serves ?? d.by?.serves } : by;
      if (fromOther || d.seq < seq) { routes.clear(); seq = 0; loaded = false; }
      const first = !loaded, fresh = [];
      for (const r of d.routes) {
        if (!routes.has(r.id) && !first) fresh.push(r.id);
        routes.set(r.id, whole(r));
      }
      if (Array.isArray(d.ids)) {
        const kept = new Set(d.ids);
        for (const id of routes.keys()) if (!kept.has(id)) routes.delete(id);
      }
      for (const id of [...routes.keys()].sort((a, b) => a - b).slice(0, -KEEP)) routes.delete(id);
      seq = d.seq || seq;
      loaded = true;
      if (first) {
        cur = newest();
        if (cur) { sync(true); render(); } else empty();
        if (seen && shown()) for (const u of underWay()) if (!playing.has(u.id)) play(u.id);
      } else {
        cur = newest();
        if (cur) sync(); else empty();
        const go = shown() ? fresh : [];
        for (const id of go) playing.set(id, gen);
        if (go.length) sync();
        for (const id of go) play(id, true);
        wake();
        render();
      }
      kick();
    }

    return {
      update,
      get seq() { return loaded ? seq : 0; },
      /** 合并后的完整 trace：其余模块（上下文格子、额度「回答中」）照旧读它 */
      trace() { return { seq, routes: [...routes.values()].sort((a, b) => a.id - b.id), pid: by?.pid, serves: by?.serves }; },
      setGateway(addr) { if (addr) { gateway = addr; hubText(); } },
      layout,
      stage,
    };
  }

  window.MagpieStage = MagpieStage;
})();
